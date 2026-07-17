#!/usr/bin/env bash
# scut-router.sh — SCUT Core-Router (cross-bobiverse).
#
# Liest NORMALISIERTE Events (von scripts/channels/<channel>.sh) von stdin, EIN Event pro Zeile,
# triagiert sie datengetrieben und routet sie ins Ziel-Bobiverse bzw. in die Review-Queue.
#
# ── Normalisiertes Event-Format (TSV, 6 Felder, von JEDEM Channel-Adapter erzeugt) ──────────────
#   channel   external_id   ts_epoch   sender   target   text
#     channel      Herkunfts-Channel (telegram|email|github|teams)
#     external_id  channel-eigene ID (Dedup/Offset) — vom Channel verwaltet, hier nur durchgereicht
#     ts_epoch     Unix-Timestamp des Events (für Alter/Frische)
#     sender       wer hat's geschickt (Channel-Identität, z.B. "owner", "github:user")
#     target       Routing-Ziel ODER leer:
#                    "@<Agent>"   → gerichtet an einen Agenten im KONTEXT-Bobiverse
#                    "[<uid>]"    → gerichtet an ein Projekt-Bobiverse (Registry-uid)
#                    "[<uid>]@<Agent>" → beides (Projekt + Agent)
#                    ""           → UNGERICHTET → Review-Queue
#     text         der Nachrichtentext (Tabs/Newlines vom Channel bereits zu Spaces normalisiert)
#
# ── Triage (datengetrieben aus projects.registry.json [+ optional team.config]) ──────────────────
#   gerichtet  → route in die _inbox.md des Ziel-Bobiverse (als "@<Agent>" oder "@<TEAM_LEAD>")
#   ungerichtet→ in die Review-Queue (_review-queue.md im Kontext-Bobiverse) = "muss jemand prüfen"
#
# ── Interne Same-Project-Comms (Bob↔Bill via standup-Files) bleibt UNANGETASTET. ────────────────
#   Dieser Router ist NUR für externe Channel-Eingänge (Mensch/Service → Bobiverse). Agent-zu-Agent
#   im selben Projekt läuft weiter direkt über die standup-Inbox.
#
# Env:
#   DEV_TEAM_REGISTRY  Pfad zur zentralen projects.registry.json
#                      (Default: <toolhub>/projects.registry.json; toolhub = dirname(ENGINE_ROOT))
#   CONTEXT_UID        uid des Bobiverse, an dessen Channel die Events reinkamen (für @-Routing +
#                      Review-Queue-Ablage). Default: erstes aktives Projekt der Registry.
#   ENGINE_ROOT        Engine-Repo-Root (Default: 2 Ebenen über diesem Script).
#   DEV_TEAM_TZ        Zeitzone für Timestamps (Default Europe/Berlin).
#   SCUT_ROUTER_DRYRUN 1 = nur entscheiden + auf stdout berichten, NICHT in Dateien schreiben.
#   SCUT_FLAG_SUSPICIOUS  1 = billige, additive Heuristik auf Prompt-Injection-Phrasierung im
#                      Payload-Text (opt-in, Default aus) hängt ein sichtbares `⚠️[SUSPECT]` an
#                      die geroutete Zeile. Flaggt NUR, blockt NIE — siehe is_suspicious() unten.
#   --self-test        baut eine Demo-Registry + Events, prüft die Triage ohne echte Inbox.
#
# ── #57 Inbound-Injection-Gate (Konvergenzpunkt) ──────────────────────────────────────────────
# Dieser Router ist der Punkt, an dem JEDER Fremdtext-Kanal (Telegram/Email/GitHub/Teams, künftig
# weitere) auf die Kanon-Inbox trifft — die Zeile, die hier gebaut wird, landet unverändert in
# `_inbox.md`/`_review-queue.md`. `route_event()` kollabiert deshalb CR/LF und `|` in jedem
# attacker-/kanal-beeinflussten Feld (sender, text, agent), BEVOR die Zeile gebaut wird — siehe
# `collapse_untrusted()`. Das ist eine Konvergenz-Garantie: sie gilt unabhängig davon, ob der
# jeweilige Channel-Adapter selbst schon normalisiert (telegram.sh/email.sh tun das für Whitespace
# bereits via Python-`split()`; dieser Router verlässt sich NICHT darauf). **Grenze** (dokumentiert
# in team-rules/untrusted-input.md): ein roher, nicht escapeter `\n` INNERHALB eines TSV-Feldes
# spaltet den Event-Stream schon VOR `route_event()` (Zeilen-Wire-Format, `run_stream()` liest
# zeilenweise) — das kann kein Feld-Kollaps HIER mehr reparieren. Die Pflicht, kein rohes `\n`
# auf die Pipe zu geben, liegt beim jeweiligen Channel-Adapter (Kanal-Ingress), nicht beim Router.
set -uo pipefail

BIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENGINE_ROOT="${ENGINE_ROOT:-$(cd "$BIN_DIR/.." && pwd)}"
TOOLHUB="$(cd "$ENGINE_ROOT/.." && pwd)"
REGISTRY="${DEV_TEAM_REGISTRY:-$TOOLHUB/projects.registry.json}"
TZc="${DEV_TEAM_TZ:-Europe/Berlin}"
DRYRUN="${SCUT_ROUTER_DRYRUN:-0}"

# expand_tilde <pfad> — die Registry speichert ~ literal; hier auf $HOME expandieren.
expand_tilde() { case "$1" in "~"/*) printf '%s' "$HOME/${1#\~/}";; *) printf '%s' "$1";; esac; }

# reg_lookup <uid> <feld> — gibt das Feld eines Registry-Eintrags aus (leer wenn nicht gefunden).
reg_lookup() {
  REG_FILE="$REGISTRY" REG_UID="$1" REG_FIELD="$2" python3 - <<'PY'
import json, os, sys
try:
    with open(os.environ["REG_FILE"]) as fh:
        data = json.load(fh)
except Exception:
    sys.exit(0)
uid, field = os.environ["REG_UID"], os.environ["REG_FIELD"]
for p in data.get("projects", []):
    if isinstance(p, dict) and p.get("uid") == uid:
        sys.stdout.write(str(p.get(field, "")))
        break
PY
}

# default_context_uid — erstes aktives Projekt der Registry (Fallback für CONTEXT_UID).
default_context_uid() {
  REG_FILE="$REGISTRY" python3 - <<'PY'
import json, os, sys
try:
    with open(os.environ["REG_FILE"]) as fh:
        data = json.load(fh)
except Exception:
    sys.exit(0)
for p in data.get("projects", []):
    if isinstance(p, dict) and p.get("status", "active") == "active":
        sys.stdout.write(p.get("uid", "")); break
PY
}

CONTEXT_UID="${CONTEXT_UID:-$(default_context_uid)}"

# team_lead_of <uid> — TEAM_LEAD aus der dev-team.env des Projekts (für @-Default bei ungenanntem Agent).
team_lead_of() {
  local path; path="$(expand_tilde "$(reg_lookup "$1" path)")"
  local env="$path/_dev_team/dev-team.env"
  [ -f "$env" ] || { printf 'Bob'; return; }
  local lead; lead="$(sed -n 's/^export TEAM_LEAD="\{0,1\}\([^"]*\)"\{0,1\}.*/\1/p' "$env" | head -n1)"
  printf '%s' "${lead:-Bob}"
}

# inbox_of <uid> — Pfad zur _inbox.md im standup-Ordner des Projekts.
inbox_of() {
  local sd; sd="$(expand_tilde "$(reg_lookup "$1" standup)")"
  [ -n "$sd" ] && printf '%s/_inbox.md' "$sd"
}

# review_queue_of <uid> — Pfad zur Review-Queue (ungerichtete Eingänge) im standup-Ordner.
review_queue_of() {
  local sd; sd="$(expand_tilde "$(reg_lookup "$1" standup)")"
  [ -n "$sd" ] && printf '%s/_review-queue.md' "$sd"
}

# collapse_untrusted <text> — #57: Newline-/Pipe-Kollaps für jedes attacker-/kanal-beeinflusste
#   Feld, bevor es in eine Kanon-Zeile eingebaut wird.
#   CR/LF → je ein Leerzeichen: ein Zeilenumbruch im Payload ist die schärfste Waffe eines
#     Angreifers — unkollabiert könnte er (bei einem Feld, das den Wire-Split von run_stream()
#     schon hinter sich hat, z.B. per \r, das `read -r` nicht als Zeilenende zählt) eine
#     angreifer-kontrollierte zusätzliche Struktur in die Ziel-Datei einschleusen.
#   `|` → `¦` (U+00A6 BROKEN BAR): das Dashboard und andere Konsumenten parsen Inbox-Zeilen naiv
#     per `split('|')` (dashboard/server/api/inbox.get.ts) — ein Payload-Pipe könnte sonst ein
#     zusätzliches Feld vortäuschen (am ehesten im `agent`-Feld relevant, das direkt zwischen dem
#     ersten und zweiten Trenn-Pipe der Zeile steht). Content-Fidelity-Tradeoff bewusst akzeptiert:
#     ein legitimes `|` im Text wird sichtbar (aber lesbar) verändert — das ist der Preis für
#     Fälschungssicherheit der Inbox-Struktur (siehe team-rules/untrusted-input.md).
collapse_untrusted() {
  local s="$1"
  s="${s//$'\r'/ }"
  s="${s//$'\n'/ }"
  s="${s//|/¦}"
  printf '%s' "$s"
}

# is_suspicious <text> — SCUT_FLAG_SUSPICIOUS=1 (Default aus): billige, additive Heuristik auf
#   grobe Prompt-Injection-Phrasierung. Läuft auf dem ROHEN Text (VOR collapse_untrusted, damit
#   das "curl … | sh"-Muster noch das echte Trennzeichen sieht) — flaggt NUR sichtbar
#   (⚠️[SUSPECT] an die Zeile), blockt NIE. False positives sind hier bewusst billiger als
#   verpasste echte Versuche; der Lead entscheidet selbst, was er mit dem Marker macht.
is_suspicious() {
  printf '%s' "$1" | grep -qiE \
    'ignore (previous|all) instructions|you are now|\b(run|execute)\b|(curl|wget)[^|]*\|[[:space:]]*(sh|bash)\b'
}

# parse_target "<target>"  → setzt globale TGT_UID + TGT_AGENT (entweder kann leer sein).
parse_target() {
  local t="$1"; TGT_UID=""; TGT_AGENT=""
  case "$t" in
    "["*"]"*) TGT_UID="${t#[}"; TGT_UID="${TGT_UID%%]*}"; t="${t#*]}";;
  esac
  case "$t" in
    "@"*) TGT_AGENT="${t#@}";;
  esac
}

route_event() {
  local channel="$1" ts_epoch="$3" sender="$4" target="$5" text="$6"
  local ts; ts="$(TZ="$TZc" date -d "@${ts_epoch:-$(date +%s)}" '+%Y-%m-%d %H:%M' 2>/dev/null \
                 || TZ="$TZc" date '+%Y-%m-%d %H:%M')"

  # #57: Suspect-Heuristik auf dem ROHEN Text (vor dem Kollaps — "curl … | sh" braucht das
  # echte Trennzeichen); das Ergebnis wird erst nach dem Line-Bau als Suffix angehängt.
  local suspect_suffix=""
  if [ "${SCUT_FLAG_SUSPICIOUS:-0}" = 1 ] && is_suspicious "$text"; then
    suspect_suffix=" ⚠️[SUSPECT]"
  fi

  # #57: Newline-/Pipe-Kollaps an der Konvergenz ALLER Kanäle (Details/Grenzen: Header oben +
  # team-rules/untrusted-input.md) — unabhängig davon, ob der Channel-Adapter selbst normalisiert.
  sender="$(collapse_untrusted "$sender")"
  text="$(collapse_untrusted "$text")"

  parse_target "$target"
  local dest_uid="$CONTEXT_UID"
  [ -n "$TGT_UID" ] && dest_uid="$TGT_UID"

  if [ -z "$target" ]; then
    # ── UNGERICHTET → Review-Queue des Kontext-Bobiverse ──
    local q; q="$(review_queue_of "$CONTEXT_UID")"
    local line; line="$ts | UNGERICHTET (via $channel, von $sender) | $text$suspect_suffix"
    if [ "$DRYRUN" = 1 ] || [ -z "$q" ]; then
      printf 'ROUTE  review-queue[%s]  ← %s\n' "$CONTEXT_UID" "$text"
    else
      mkdir -p "$(dirname "$q")"; printf '%s\n' "$line" >> "$q"
      printf 'ROUTE  review-queue[%s] (%s)  ← %s\n' "$CONTEXT_UID" "$q" "$text"
    fi
    return
  fi

  # ── GERICHTET → _inbox.md des Ziel-Bobiverse ──
  local agent="$TGT_AGENT"
  [ -z "$agent" ] && agent="$(team_lead_of "$dest_uid")"   # Projekt genannt, aber kein Agent → Lead
  agent="$(collapse_untrusted "$agent")"   # #57: target-Feld ist kanal-/attacker-beeinflusst
  local ib; ib="$(inbox_of "$dest_uid")"
  local line; line="$ts | @$agent | SCUT (via $channel, von $sender): $text$suspect_suffix"
  if [ "$DRYRUN" = 1 ] || [ -z "$ib" ]; then
    printf 'ROUTE  inbox[%s] @%s  ← %s\n' "$dest_uid" "$agent" "$text"
  else
    mkdir -p "$(dirname "$ib")"; printf '%s\n' "$line" >> "$ib"
    printf 'ROUTE  inbox[%s] @%s (%s)  ← %s\n' "$dest_uid" "$agent" "$ib" "$text"
  fi
}

run_stream() {
  local n=0
  # Ganze Zeile lesen + selbst tab-splitten. NICHT `read ... <IFS=tab>` benutzen:
  # Tab ist ein IFS-Whitespace-Zeichen → bash kollabiert aufeinanderfolgende Tabs zu EINEM
  # Delimiter, wodurch ein leeres Mittelfeld (z.B. ungerichtetes/leeres target) die Spalten
  # verschiebt (target würde fälschlich den text-Wert schlucken). Manuelles Split per
  # Parameter-Expansion erhält leere Felder positionsgetreu (text = Rest, darf Tabs enthalten).
  local line channel external_id ts_epoch sender target text rest
  # cut_field: erstes Tab-Feld von $rest abschneiden → globale $_F, Rest zurück in $rest.
  # Erhält leere Felder; fehlt der Tab, ist das Restfeld der ganze Wert und $rest danach leer.
  cut_field() {
    case "$rest" in
      *$'\t'*) _F="${rest%%$'\t'*}"; rest="${rest#*$'\t'}";;
      *)       _F="$rest";          rest="";;
    esac
  }
  while IFS= read -r line || [ -n "$line" ]; do
    [ -z "$line" ] && continue
    rest="$line"
    cut_field; channel="$_F"
    cut_field; external_id="$_F"
    cut_field; ts_epoch="$_F"
    cut_field; sender="$_F"
    cut_field; target="$_F"
    text="$rest"
    [ -z "${channel:-}" ] && continue
    route_event "$channel" "$external_id" "$ts_epoch" "$sender" "$target" "$text"
    n=$((n+1))
  done
  printf '── scut-router: %d Event(s) verarbeitet (context=%s, registry=%s)\n' \
    "$n" "$CONTEXT_UID" "$REGISTRY" >&2
}

self_test() {
  # EXIT- statt RETURN-Trap: der RETURN-Trap-Befehl (rm) kann unter `set -o pipefail`
  # den Funktions-Return-Status verschleiern → Self-Test meldete „ROT", Script exitete aber 0.
  # Mit EXIT-Trap + explizitem `exit` (siehe case unten) propagiert der Status zuverlässig.
  # tmp bewusst GLOBAL (kein local): der EXIT-Trap feuert nach Funktions-Ende — ein local
  # wäre dort out-of-scope und knallt unter `set -u` ("tmp: unbound variable").
  tmp="$(mktemp -d "${TMPDIR:-/tmp}/scut-router-test.XXXXXX")"
  trap 'rm -rf "$tmp"' EXIT
  mkdir -p "$tmp/alpha/_dev_team/standup" "$tmp/beta/_dev_team/standup"
  cat > "$tmp/registry.json" <<JSON
{ "version":1, "projects":[
  {"uid":"alpha","name":"alpha","label":"Alpha","path":"$tmp/alpha","standup":"$tmp/alpha/_dev_team/standup","theme":"bobiverse","status":"active"},
  {"uid":"beta","name":"beta","label":"Beta","path":"$tmp/beta","standup":"$tmp/beta/_dev_team/standup","theme":"bobiverse","status":"active"}
]}
JSON
  printf 'export TEAM_LEAD="Bob"\n'  > "$tmp/alpha/_dev_team/dev-team.env"
  printf 'export TEAM_LEAD="Zoe"\n'  > "$tmp/beta/_dev_team/dev-team.env"

  local now; now="$(date +%s)"
  # 4 Events: @Bill (gerichtet, Kontext alpha) · [beta] (Projekt, kein Agent→Lead Zoe) ·
  #           [beta]@Cid (beides) · ungerichtet (→ Review-Queue alpha)
  local events
  events="$(printf '%s\n' \
    "telegram	1	$now	owner	@Bill	bitte API-Key rotieren" \
    "email	2	$now	extern	[beta]	Vertrag liegt bei" \
    "github	3	$now	user	[beta]@Cid	PR review?" \
    "teams	4	$now	chef	$(printf '')	wer kann das mal anschauen")"

  DEV_TEAM_REGISTRY="$tmp/registry.json" CONTEXT_UID="alpha" \
    printf '%s\n' "$events" | DEV_TEAM_REGISTRY="$tmp/registry.json" CONTEXT_UID="alpha" "$BIN_DIR/scut-router.sh" >/dev/null 2>&1

  local fail=0
  check() { if grep -qF "$2" "$1" 2>/dev/null; then printf '  ✓ %s\n' "$3"; else printf '  ✗ %s (in %s)\n' "$3" "$1"; fail=1; fi; }

  check "$tmp/alpha/_dev_team/standup/_inbox.md"        "@Bill"  "@Bill → alpha-inbox (gerichteter Agent, Kontext)"
  check "$tmp/beta/_dev_team/standup/_inbox.md"         "@Zoe"   "[beta] ohne Agent → beta-Lead Zoe"
  check "$tmp/beta/_dev_team/standup/_inbox.md"         "@Cid"   "[beta]@Cid → beta-inbox @Cid"
  check "$tmp/alpha/_dev_team/standup/_review-queue.md" "UNGERICHTET" "ungerichtet → alpha-Review-Queue"

  if [ "$fail" = 0 ]; then echo "scut-router self-test: GRÜN"; return 0
  else echo "scut-router self-test: ROT"; return 1; fi
}

case "${1:-}" in
  --self-test|self-test) self_test; exit $? ;;
  "" ) run_stream ;;
  * ) echo "Usage: <channel.sh> | scut-router.sh   |   scut-router.sh --self-test" >&2; exit 64 ;;
esac
