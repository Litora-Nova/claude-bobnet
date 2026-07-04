#!/usr/bin/env bash
# inbox-watch.sh — Inbox-Watcher: prüft alle Projekt-Eingänge, nudgt idle Leads (Issue #44).
#
# Warum: Alle externen Kanäle (Telegram/Email via channels→Router, Menschen, andere Bobs)
# konvergieren per Kanon auf die standup-`_inbox.md` — aber ein headless Lead liest sie nur
# bei Boot/Stand-up. Dieser Watcher schließt die letzte Meile: neue Einträge + Lead idle →
# kurzer Nudge via mux_send. Er kapert KEINE Prompts (comms.md §5: Inbox-first; busy = in Ruhe).
#
# EIN Durchlauf pro Aufruf (cron-/systemd-timer-freundlich; Kadenz macht der Timer, z.B. 2–5 min).
#
# Pro aktivem Registry-Projekt:
#   1. Watch-Zustand: Größe der `_inbox.md` + Dateizahl in `_inbox/` gegen State-File vergleichen.
#   2. Bei Neuem den Lead-Zustand lesen (Heartbeat-Log `<standup>/<TEAM_LEAD>.log`):
#        idle|done|kein Log     → NUDGE (wenn MUX_SESSION konfiguriert + Session lebt)
#        busy älter als STALE   → NUDGE (vergessener busy-Status blockiert sonst ewig)
#        busy (frisch)|blocked  → SKIP (State bleibt → nächster Tick prüft erneut)
#        Session down           → report (opt-in Boot via INBOX_WATCH_BOOT=1 + BOOT_CMD)
#   3. State fortschreiben NUR wenn genudged/berichtet — busy-Skips bleiben „offen".
#
# Instanz-Kontrakt (`<projekt>/_dev_team/dev-team.env`, alles optional):
#   TEAM_LEAD     Name, unter dem der Lead heartbeatet (Log-Dateiname). Default: Bob.
#   MUX_SESSION   Multiplexer-Session des Leads (für den Nudge). Fehlt → report-only.
#   BOOT_CMD      Start-Kommando des Leads (nur mit INBOX_WATCH_BOOT=1 genutzt).
#
# Env:
#   DEV_TEAM_REGISTRY       zentrale projects.registry.json (Default wie scut-router.sh)
#   INBOX_WATCH_STATE       State-Dir (Default ~/.claude/inbox-watch)
#   INBOX_WATCH_STALE_MIN   busy gilt nach N Minuten als stale (Default 90)
#   INBOX_WATCH_BOOT        1 = Lead bei Session-down via mux_boot wecken (Default 0)
#   INBOX_WATCH_DRYRUN      1 = keine mux-Aufrufe (Nudge gilt als zugestellt); State läuft wie echt
#
# Exit immer 0 (Monitoring, kein Gate). Host-Verdrahtung (Timer/Enable) = Instanz + {HUMAN} (T4).
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENGINE_ROOT="${ENGINE_ROOT:-$(cd "$DIR/.." && pwd)}"
TOOLHUB="$(cd "$ENGINE_ROOT/.." && pwd)"
REGISTRY="${DEV_TEAM_REGISTRY:-$TOOLHUB/projects.registry.json}"
STATE_DIR="${INBOX_WATCH_STATE:-$HOME/.claude/inbox-watch}"
STALE_MIN="${INBOX_WATCH_STALE_MIN:-90}"
DO_BOOT="${INBOX_WATCH_BOOT:-0}"
DRYRUN="${INBOX_WATCH_DRYRUN:-0}"
. "$DIR/lib/boot.sh"   # liefert mux_boot + (via mux.sh) mux_has/mux_send

mkdir -p "$STATE_DIR"

# env_of <envfile> <key> — export KEY="wert" / export KEY=wert lesen (leer wenn fehlt).
env_of() { [ -f "$1" ] && sed -n "s/^export $2=\"\{0,1\}\([^\"]*\)\"\{0,1\}.*/\1/p" "$1" | head -n1; }

# expand_tilde — Registry speichert ~ ggf. literal (wie scut-router.sh).
expand_tilde() { case "$1" in "~"/*) printf '%s' "$HOME/${1#\~/}";; *) printf '%s' "$1";; esac; }

# lead_state <log> — "idle|done|busy|blocked|none" + Alter in Minuten als "status:age".
lead_state() {
  local log="$1"
  [ -f "$log" ] || { printf 'none:0'; return; }
  local last; last="$(tail -n1 "$log")"
  local ts st
  ts="$(printf '%s' "$last" | cut -d'|' -f1 | sed 's/[[:space:]]*$//')"
  st="$(printf '%s' "$last" | cut -d'|' -f2 | tr -d ' ')"
  local es now age=0
  es="$(date -d "$ts" +%s 2>/dev/null || echo 0)"; now="$(date +%s)"
  [ "$es" -gt 0 ] && age=$(( (now-es)/60 ))
  printf '%s:%s' "${st:-none}" "$age"
}

# watch_sig <standup> — Signatur "größe:anzahl" von _inbox.md + _inbox/.
watch_sig() {
  local sd="$1" size=0 cnt=0
  [ -f "$sd/_inbox.md" ] && size="$(wc -c < "$sd/_inbox.md" | tr -d ' ')"
  [ -d "$sd/_inbox" ] && cnt="$(find "$sd/_inbox" -type f 2>/dev/null | wc -l | tr -d ' ')"
  printf '%s:%s' "$size" "$cnt"
}

# Aktive Projekte als TSV "uid<TAB>path<TAB>standup" aus der Registry.
projects() {
  REG_FILE="$REGISTRY" python3 - <<'PY'
import json, os, sys
try:
    with open(os.environ["REG_FILE"]) as fh:
        data = json.load(fh)
except Exception:
    sys.exit(0)
for p in data.get("projects", []):
    if isinstance(p, dict) and p.get("status", "active") == "active":
        print("%s\t%s\t%s" % (p.get("uid",""), p.get("path",""), p.get("standup","")))
PY
}

n_new=0; n_nudge=0
while IFS=$'\t' read -r uid path standup; do
  [ -z "$uid" ] && continue
  standup="$(expand_tilde "$standup")"; path="$(expand_tilde "$path")"
  [ -f "$standup/_inbox.md" ] || { echo "[inbox-watch] $uid: keine _inbox.md — skip"; continue; }

  sig="$(watch_sig "$standup")"
  statef="$STATE_DIR/$uid.state"
  old="$(cat "$statef" 2>/dev/null || echo "")"
  if [ "$sig" = "$old" ]; then
    echo "[inbox-watch] $uid: ok (unverändert)"
    continue
  fi
  n_new=$((n_new+1))

  envf="$path/_dev_team/dev-team.env"
  lead="$(env_of "$envf" TEAM_LEAD)"; lead="${lead:-Bob}"
  session="$(env_of "$envf" MUX_SESSION)"
  st_age="$(lead_state "$standup/$lead.log")"
  st="${st_age%%:*}"; age="${st_age##*:}"

  decide="nudge"
  case "$st" in
    busy)    [ "$age" -lt "$STALE_MIN" ] && decide="skip-busy" ;;
    blocked) decide="skip-blocked" ;;
  esac

  if [ "$decide" != "nudge" ]; then
    echo "[inbox-watch] $uid: NEU, aber Lead $lead=$st (${age}min) — $decide (State bleibt offen)"
    continue
  fi

  if [ -z "$session" ]; then
    echo "[inbox-watch] $uid: NEU, Lead $lead=$st — report-only (kein MUX_SESSION konfiguriert)"
    printf '%s' "$sig" > "$statef"
    continue
  fi

  if [ "$DRYRUN" = 1 ]; then
    echo "[inbox-watch] $uid: NUDGE → $session (dryrun)"
    printf '%s' "$sig" > "$statef"; n_nudge=$((n_nudge+1))
    continue
  fi

  if mux_has "$session" 2>/dev/null; then
    if mux_send "$session" "📬 [$uid] Neue Inbox-Einträge — bitte $standup/_inbox.md lesen." 2>/dev/null; then
      echo "[inbox-watch] $uid: NUDGE → $session (Lead $lead war $st)"
      printf '%s' "$sig" > "$statef"; n_nudge=$((n_nudge+1))
    else
      echo "[inbox-watch] $uid: NUDGE an $session fehlgeschlagen — State bleibt offen"
    fi
  else
    if [ "$DO_BOOT" = 1 ]; then
      boot_cmd="$(env_of "$envf" BOOT_CMD)"
      if [ -n "$boot_cmd" ] && mux_boot "$session" "$boot_cmd" "" >/dev/null 2>&1; then
        echo "[inbox-watch] $uid: Session down → GEBOOTET ($session; liest Inbox beim Start)"
        printf '%s' "$sig" > "$statef"; n_nudge=$((n_nudge+1))
      else
        echo "[inbox-watch] $uid: Session down, Boot nicht möglich (BOOT_CMD fehlt/Fehler) — State offen"
      fi
    else
      echo "[inbox-watch] $uid: NEU, aber Session $session down (Boot aus) — State bleibt offen"
    fi
  fi
done <<< "$(projects)"

echo "── inbox-watch: $n_new Projekt(e) mit Neuem, $n_nudge genudged/gebootet (registry=$REGISTRY)"
exit 0
