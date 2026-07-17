#!/usr/bin/env bash
# bridge-receive.sh <peer> — Empfänger der BobNet-Bridge (forced command, Issue #45).
#
# Läuft als FORCED COMMAND eines dedizierten Bridge-SSH-Keys (eine authorized_keys-Zeile
# pro Peer/Richtung, mit `restrict` + `from=` gepinnt — Layout: Host-Trust-Doc der Instanz).
# Der Peer-Name kommt als ARGUMENT aus der authorized_keys-Zeile (authentische Identität,
# nie vom Client); die Nachricht kommt als DATEN aus SSH_ORIGINAL_COMMAND (Fallback stdin)
# und wird NIEMALS ausgeführt.
#
# Sicherheits-Kontrakt (Serverwächter-Design 2026-07-04):
#   - max 4 KB (Bytes, nicht Zeichen — multibyte-sicher, Codex-Review M4/#51), GENAU eine Zeile,
#     Control-Chars werden gestrippt (Tab → Space)
#   - Pflicht-Adressierung: führendes `[<uid>]` oder `[<uid>]@<Agent>`
#     (Regex ^\[[a-z0-9_-]{1,32}\](@[A-Za-z0-9_-]{1,32})?$) — sonst REJECT
#   - Peer-Argument selbst muss ^[A-Za-z0-9_-]{1,32}$ matchen; Display-Namen aus zweiter Hand
#     (peers.json `lead`, TEAM_LEAD-Fallback aus dev-team.env) werden Steuerzeichen/Newline-
#     gestrippt + auf 64 Zeichen gecappt — verhindert gefälschte Log-/Inbox-Zeilen (Codex-Review
#     L7/#51)
#   - Ziel-Inbox löst der EMPFÄNGER aus der Registry auf (Client kann keinen Pfad wählen);
#     [uid] ohne Agent → TEAM_LEAD des Projekts (dev-team.env, Default Bob)
#   - Kanon-Zeile wird SERVERSEITIG gestempelt: `<ts> | @<Agent> | BRIDGE (<peer>): <text>`
#     (+ Signatur `— (<lead>@<peer>)`, wenn peers.json den Peer-Lead kennt); Append mit flock
#   - Audit-PFLICHT: jede Annahme/Ablehnung → $BRIDGE_LOG (ts · accept/reject+Grund · peer ·
#     target · bytes · Auszug). Fail-closed VOR der Zustellung (Codex-Review M3/#51): ist der
#     Log-Pfad nicht schreibbar (Preflight), wird NICHT zugestellt (siehe Exit 3). Der
#     ACCEPT-Eintrag selbst wird erst NACH erfolgreichem Inbox-Append geschrieben (R1/#52) —
#     sonst stünde bei einem Append-Fehlschlag ein ACCEPT gefolgt von "REJECT: Append
#     fehlgeschlagen" für dieselbe Nachricht im Log (widersprüchlich). Ein REJECT wird dagegen
#     IMMER abgelehnt, auch wenn dessen Audit-Write scheitert (best-effort dort).
#   - Exit 0 = zugestellt · 2 = REJECT (Sender darf NICHT blind retryn) ·
#     3 = Infra-Fehler: Audit-Log-Preflight fehlgeschlagen, NICHT zugestellt (fail-closed, kein
#     Zustellversuch ohne funktionierenden Audit-Kanal)
#   - #57: Payload-Pipe wird zu `¦` (broken bar) kollabiert — sowohl die Kanon-Zeile als auch
#     das eigene " | "-getrennte Audit-Log (audit()) sind sonst Feld-Fälschung ausgesetzt. CR/LF
#     sind bereits durch den Ein-Zeile-Kontrakt ausgeschlossen (mehrzeilig → REJECT).
#
# Kanon (#58, `team-rules/verb-gateway.md`): dieses Script IST die Referenz-Implementierung des
# Forced-Command-Gateway-Musters (Verb-Allowlist + Audit-Log + Byte-/Zeilen-Limit) — die
# `authorized_keys`-Zeile MUSS dem `bridge:<peer>`-Kommentar-Kanon folgen, damit ein Aufräumen
# sie nicht fälschlich als Altlast entfernt, während ein voller Shell-Key desselben Peers
# überlebt (genau umgekehrt zur Härtungsabsicht — Feld-Regression, s. verb-gateway.md).
#
# Env:
#   DEV_TEAM_REGISTRY  zentrale projects.registry.json (Default wie scut-router.sh)
#   BOBNET_PEERS       peers.json (Default-Auflösung wie bobnet-send.sh) — nur für Peer-Lead-Signatur
#   BRIDGE_LOG         Audit-Log (Default $HOME/standup/bridge.log, sonst $HOME/.claude/bobiverse-bridge.log)
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENGINE_ROOT="${ENGINE_ROOT:-$(cd "$DIR/.." && pwd)}"
TOOLHUB="$(cd "$ENGINE_ROOT/.." && pwd)"
REGISTRY="${DEV_TEAM_REGISTRY:-$TOOLHUB/projects.registry.json}"

PEER="${1:-}"
if [ -n "${BRIDGE_LOG:-}" ]; then LOG="$BRIDGE_LOG"
elif [ -d "$HOME/standup" ]; then LOG="$HOME/standup/bridge.log"
else LOG="$HOME/.claude/bobiverse-bridge.log"; fi

audit() { # audit <ACCEPT|REJECT grund> <target> <bytes> <auszug> — Exit-Status = Schreiberfolg
  mkdir -p "$(dirname "$LOG")" 2>/dev/null
  printf '%s | %s | peer=%s | target=%s | %sB | %s\n' \
    "$(date '+%Y-%m-%d %H:%M:%S')" "$1" "${PEER:-?}" "${2:-—}" "${3:-0}" "${4:-}" >> "$LOG" 2>/dev/null
}
# REJECT bleibt REJECT, auch wenn dessen Audit-Write scheitert (best-effort) — nur der
# ACCEPT-Pfad unten ist fail-closed (M3/#51).
reject() { audit "REJECT: $1" "${2:-—}" "${3:-0}" "${4:-}" || true; echo "bridge-receive: REJECT — $1" >&2; exit 2; }

# PEER: Steuerzeichen/Newline sofort weg (Log-Spoofing-Schutz, L7/#51), dann strikt validieren —
# so tragen auch die REJECT-Audit-Zeilen unten nie einen rohen Newline im peer=-Feld.
PEER="$(printf '%s' "$PEER" | tr -d '\000-\037\177')"
[ -n "$PEER" ] || reject "kein Peer-Argument (authorized_keys-Zeile prüfen)"
case "$PEER" in
  *[!A-Za-z0-9_-]*) reject "ungültiger Peer-Name (erlaubt: A-Za-z0-9_-, max 32) — Log-Spoofing-Schutz (L7)";;
esac
[ "${#PEER}" -le 32 ] || reject "Peer-Name zu lang (>32) — Log-Spoofing-Schutz (L7)"

# ── Input: SSH_ORIGINAL_COMMAND als Daten, Fallback stdin; max 4 KB ─────────────────────────
raw="${SSH_ORIGINAL_COMMAND:-}"
[ -z "$raw" ] && raw="$(head -c 5000 2>/dev/null || true)"
# Bytes zählen, nicht Zeichen (M4/#51): ${#raw} zählt in Multibyte-Locales Codepoints, nicht
# Bytes — eine UTF-8-lastige Nachricht könnte so den 4KB-Bytekontrakt sprengen (und den
# Audit-Bytewert verfälschen), ohne von der Zeichen-basierten Prüfung erfasst zu werden.
bytes="$(printf '%s' "$raw" | LC_ALL=C wc -c | tr -d ' ')"
[ "$bytes" -gt 0 ] || reject "leere Nachricht" "—" 0
[ "$bytes" -le 4096 ] || reject "über 4KB (${bytes}B)" "—" "$bytes"
raw="${raw%$'\n'}"                                   # EIN trailing newline (stdin) ist ok
case "$raw" in *$'\n'*) reject "mehr als eine Zeile" "—" "$bytes";; esac
text="$(printf '%s' "$raw" | tr '\t' ' ' | tr -d '\000-\010\012-\037\177')"
[ -n "${text// /}" ] || reject "leer nach Sanitize" "—" "$bytes"

# ── Pflicht-Target extrahieren + validieren ─────────────────────────────────────────────────
tgt="$(printf '%s' "$text" | grep -oE '^\[[a-z0-9_-]{1,32}\](@[A-Za-z0-9_-]{1,32})?' | head -n1)"
[ -n "$tgt" ] || reject "kein/ungültiges Target (Pflicht: [uid] oder [uid]@Agent)" "—" "$bytes" "${text:0:60}"
rest="${text#"$tgt"}"; rest="${rest#:}"; rest="${rest## }"; rest="${rest%% }"
rest="$(printf '%s' "$rest" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')"
[ -n "$rest" ] || reject "leerer Text nach Target" "$tgt" "$bytes"
# #57: Payload-Pipe → ¦ (broken bar) — dieselbe Konvergenzpunkt-Härtung wie scut-router.sh
# collapse_untrusted(). CR/LF sind hier bereits durch den Ein-Zeile-Kontrakt oben ausgeschlossen
# (mehrzeilig → REJECT, s. o.); ein rohes "|" im Payload würde aber sowohl die " | "-getrennte
# Kanon-Zeile (unten) ALS AUCH das eigene " | "-getrennte Audit-Log (audit(), unten) fälschen
# können — deshalb VOR beiden Verwendungen kollabieren, nicht erst an einer Stelle.
rest="${rest//|/¦}"
uid="${tgt#[}"; uid="${uid%%]*}"
agent="${tgt#*]}"; agent="${agent#@}"

# ── Ziel-Inbox löst der Empfänger auf (Registry; kein Client-Pfad, kein Traversal) ──────────
expand_tilde() { case "$1" in "~"/*) printf '%s' "$HOME/${1#\~/}";; *) printf '%s' "$1";; esac; }
reg_lookup() {
  REG_FILE="$REGISTRY" REG_UID="$1" REG_FIELD="$2" python3 - <<'PY'
import json, os, sys
try:
    with open(os.environ["REG_FILE"]) as fh:
        data = json.load(fh)
except Exception:
    sys.exit(0)
for p in data.get("projects", []):
    if isinstance(p, dict) and p.get("uid") == os.environ["REG_UID"]:
        sys.stdout.write(str(p.get(os.environ["REG_FIELD"], "")))
        break
PY
}
standup="$(expand_tilde "$(reg_lookup "$uid" standup)")"
[ -n "$standup" ] || reject "unbekannte uid '$uid' (nicht in Registry)" "$tgt" "$bytes"
inbox="$standup/_inbox.md"

if [ -z "$agent" ]; then
  proj="$(expand_tilde "$(reg_lookup "$uid" path)")"
  envf="$proj/_dev_team/dev-team.env"
  if [ -f "$envf" ]; then
    agent="$(sed -n 's/^export TEAM_LEAD="\{0,1\}\([^"]*\)"\{0,1\}.*/\1/p' "$envf" | head -n1)"
    # Aus einer Konfig-Datei gelesen, nicht aus dem client-validierten [uid]@Agent-Regex —
    # Steuerzeichen/Newline strippen + Länge cappen, damit dev-team.env keine gefälschten
    # Log-/Inbox-Zeilen einschleusen kann (L7/#51). #57 erweitert dieselbe Sanitize-Logik um
    # den Pipe-Kollaps (¦) — ein TEAM_LEAD mit "|" könnte sonst dieselbe Feld-Fälschung wie im
    # Payload erreichen, nur über die Config statt über den Client. Bewusst `${..//|/¦}` statt
    # `tr '|' '¦'`: tr übersetzt byteweise und zerlegt das 2-Byte-UTF-8-Zeichen ¦ (U+00A6) dabei
    # in kaputte Einzelbytes (sichtbar als „�") — Bash-Parameterexpansion ist string-/
    # zeichenbasiert und bleibt korrekt.
    agent="$(printf '%s' "$agent" | tr -d '\000-\037\177')"
    agent="${agent//|/¦}"
    agent="${agent:0:64}"
  fi
  agent="${agent:-Bob}"
fi

# ── Peer-Lead-Signatur (optional, aus peers.json des Empfängers) ────────────────────────────
peers_file="${BOBNET_PEERS:-}"
if [ -z "$peers_file" ] && [ -f "$HOME/.claude/bobiverse.json" ]; then
  peers_file="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("peers",""))' "$HOME/.claude/bobiverse.json" 2>/dev/null)"
fi
peers_file="${peers_file:-$HOME/.claude/bobiverse-peers.json}"
peers_file="$(expand_tilde "$peers_file")"
lead=""
[ -f "$peers_file" ] && lead="$(PEERS_FILE="$peers_file" PEER_NAME="$PEER" python3 - <<'PY'
import json, os
try:
    with open(os.environ["PEERS_FILE"]) as fh:
        data = json.load(fh)
    entry = data.get(os.environ["PEER_NAME"]) or {}
    print(entry.get("lead", "") if isinstance(entry, dict) else "")
except Exception:
    pass
PY
)"
# peers.json ist Config, kein client-validierter Wert — dieselbe Sanitize-Regel wie beim
# TEAM_LEAD-Fallback oben (L7/#51 + #57): Steuerzeichen/Newline weg, Pipe kollabiert (Bash-
# Parameterexpansion statt `tr` — s. Begründung beim Agent-Fallback oben), Länge gecappt.
lead="$(printf '%s' "$lead" | tr -d '\000-\037\177')"
lead="${lead//|/¦}"
lead="${lead:0:64}"

# ── Serverseitig stempeln + flock-Append ────────────────────────────────────────────────────
line="$(date '+%Y-%m-%d %H:%M') | @$agent | BRIDGE ($PEER): $rest"
[ -n "$lead" ] && line="$line — ($lead@$PEER)"

# M3/#51: Audit-Pflicht ist fail-closed für ACCEPT — ist der Audit-Kanal kaputt, wird NICHT
# zugestellt (Exit 3), statt eine Nachricht ohne Audit-Trail durchzulassen. R1/#52: dieser
# Preflight prüft NUR die Schreibbarkeit (schreibt noch KEIN "ACCEPT") — der finale
# ACCEPT-Eintrag kommt erst NACH dem erfolgreichen Inbox-Append weiter unten. Stünde ACCEPT
# schon hier und der Append scheitert danach, hinterließe das ein widersprüchliches ACCEPT
# gefolgt von "REJECT: Append fehlgeschlagen" für dieselbe Nachricht im Log.
audit_writable() { mkdir -p "$(dirname "$LOG")" 2>/dev/null; : >> "$LOG" 2>/dev/null; }
if ! audit_writable; then
  echo "bridge-receive: Audit-Log nicht schreibbar ($LOG) — NICHT zugestellt (fail-closed)" >&2
  exit 3
fi

mkdir -p "$(dirname "$inbox")"
{ flock -x 9; printf '%s\n' "$line" >&9; } 9>>"$inbox" \
  || reject "Append fehlgeschlagen ($inbox)" "$tgt" "$bytes"

# Zustellung ist bereits erfolgt — der ACCEPT-Eintrag ist jetzt reine Buchführung (best-effort
# wie bei REJECT; ein Schreibfehler hier kann die bereits erfolgte Zustellung nicht mehr
# zurückrollen, der Preflight oben hat den häufigen Fall — kaputter Log-Pfad — schon gefangen).
audit "ACCEPT" "$tgt" "$bytes" "${rest:0:60}" \
  || echo "bridge-receive: ACCEPT-Audit-Write fehlgeschlagen ($LOG) — Nachricht wurde trotzdem zugestellt" >&2

echo "✓ bridge-receive: [$uid]@$agent ← $PEER (${bytes}B)"
exit 0
