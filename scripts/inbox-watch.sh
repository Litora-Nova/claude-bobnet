#!/usr/bin/env bash
# inbox-watch.sh — Inbox-Watcher: prüft alle Projekt-Eingänge, nudgt idle Leads (Issue #44),
# verifiziert Zustellung über den Lead-Heartbeat statt über den mux_send-Returncode (Issue #48).
#
# Warum: Alle externen Kanäle (Telegram/Email via channels→Router, Menschen, andere Bobs)
# konvergieren per Kanon auf die standup-`_inbox.md` — aber ein headless Lead liest sie nur
# bei Boot/Stand-up. Dieser Watcher schließt die letzte Meile: neue Einträge + Lead idle →
# kurzer Nudge via mux_send. Er kapert KEINE Prompts (comms.md §5: Inbox-first; busy = in Ruhe).
#
# Feld-Fund 2026-07-05 (#48): ein Nudge, der den State SOFORT finalisiert, ist zu optimistisch —
# (a) report-only (kein MUX_SESSION) finalisierte bisher trotzdem, obwohl NIEMAND geweckt wurde;
# (b) zellij `write-chars`/`write 13` an eine Session OHNE attached Client landet als
# unabgeschickter Draft, der mux_send-Returncode sieht aber "ok" aus. Darum jetzt:
#
# EIN Durchlauf pro Aufruf (cron-/systemd-timer-freundlich; Kadenz macht der Timer, z.B. 2–5 min).
#
# Zustandsmaschine pro aktivem Registry-Projekt:
#   1. Signatur "größe:anzahl:queue" aus `_inbox.md` + `_inbox/` + `_review-queue.md` bilden und
#      gegen das State-File vergleichen.
#   2. State-File pro uid, zwei Formen:
#        final:   nackte Signatur (Alt-Format, weiter gelesen/geschrieben) — "bekannt/erledigt".
#        pending: "PENDING sig=<sig> lines=<N> attempts=<n>" — ein Nudge ist raus, aber NICHT
#                 über den mux_send-rc verifiziert. Verifikation läuft über den Lead-Heartbeat:
#                 `<standup>/<TEAM_LEAD>.log` hat seit dem Nudge eine NEUE Zeile bekommen
#                 (aktuelle Zeilenzahl > Snapshot bei Nudge-Zeit) — Stand-up beginnt kanonisch
#                 mit Heartbeat + Inbox lesen, ein neuer Log-Eintrag gilt also als Zustellnachweis.
#                 (Zeilenzahl statt Timestamp: `log.sh` schreibt nur Minutenauflösung — ein Nudge
#                 + Heartbeat in derselben Minute wäre über Timestamps nicht sauber unterscheidbar.)
#   3. Bei ausstehendem Pending zuerst verifizieren:
#        verifiziert                   → State finalisieren (auf die Signatur DES Nudges — ist
#                                         die aktuelle Signatur seither weitergewandert, bleibt
#                                         SIE offen und wird im selben Tick als neuer Zyklus
#                                         weiterbehandelt)
#        nicht verifiziert, Sig gleich  → Re-Nudge, Versuchszähler hoch, bis INBOX_WATCH_MAX_NUDGE
#        nicht verifiziert, Sig weiter  → neuer Zyklus (Versuchszähler resettet auf 1)
#   4. Bei Neuem den Lead-Zustand lesen (Heartbeat-Log `<standup>/<TEAM_LEAD>.log`):
#        idle|done|kein Log     → NUDGE (wenn MUX_SESSION konfiguriert + Session lebt)
#        busy älter als STALE   → NUDGE (vergessener busy-Status blockiert sonst ewig)
#        busy (frisch)|blocked  → SKIP (State bleibt „offen" → nächster Tick prüft erneut)
#        Session down           → report (opt-in Boot via INBOX_WATCH_BOOT=1 + BOOT_CMD; ein
#                                  Boot gilt als zugestellt — der SessionStart-Hook liest die
#                                  Inbox selbst, das ist zuverlässiger als ein mux_send-Nudge)
#   5. Eskalation (`INBOX_WATCH_ALERT_CMD`, opt-in) läuft GENAU EINMAL pro Vorgang, wenn (a) die
#      Re-Nudge-Versuche erschöpft sind, ohne verifiziert worden zu sein, oder (b) gar kein
#      Weckweg existiert (report-only, kein MUX_SESSION). Ohne Alert-Cmd wird trotzdem finalisiert
#      (kein Endlos-Loop) — aber laut als „VERSCHLUCKT" geloggt + in der Summary-Zeile gezählt.
#      Schlägt der Alert-Cmd selbst fehl (rc≠0), zählt das NICHT als „eskaliert" mit — eigener
#      Zähler „Alert-Fehlschlag(e)" in der Summary-Zeile (0.14.0-Gate, Riker-Fund).
#   6. State fortschreiben NUR bei Nudge (→ pending) oder Verifikation/Eskalation/report-only
#      (→ final) — busy/blocked-Skips + fehlgeschlagene Sends bleiben „offen". Eine korrupte
#      PENDING-Zeile (Pflichtfeld sig/lines/attempts fehlt oder ist nicht numerisch) wird
#      KONSERVATIV wie „kein State" behandelt — frischer Zyklus statt eines permissiven
#      Default (0.14.0-Gate, Marvin-Fund: ein defaultendes `lines=0` hätte fast jeden Heartbeat
#      sofort als Zustellnachweis durchgehen lassen).
#
#   Bekannte Grenze (Riker-Review 0.14.0): die Heartbeat-Verifikation ist eine Heuristik, kein
#   Beweis, dass die Inbox gelesen wurde — heartbeatet der Lead nach dem Nudge wegen ANDERER
#   Arbeit (z. B. ein Alt-Task), OHNE die Inbox zu öffnen, gilt der Nudge trotzdem als
#   zugestellt. Bewusst in Kauf genommen: verlässlicher als der mux_send-rc (der über eine
#   echte Reaktion gar nichts aussagt), aber eben auch keine Garantie.
#
#   Single-Instance-Guard: ein `flock` auf `<STATE_DIR>/.lock` serialisiert Timer-/Cron-Läufe
#   (Pattern aus `bridge-receive.sh`) — ein überlappender Zweitlauf wird sauber übersprungen
#   (exit 0, kein State-Touch), damit die „genau-einmal"-Eskalation nicht durch einen parallelen
#   Durchlauf verletzt werden kann.
#
# Instanz-Kontrakt (`<projekt>/_dev_team/dev-team.env`, alles optional):
#   TEAM_LEAD              Name, unter dem der Lead heartbeatet (Log-Dateiname). Default: Bob.
#   MUX_SESSION             Multiplexer-Session des Leads (für den Nudge). Fehlt → report-only.
#   BOOT_CMD                Start-Kommando des Leads (nur mit INBOX_WATCH_BOOT=1 genutzt). Läuft
#                           in einer FRISCHEN Shell (mux_spawn) — die eigene dev-team.env wird
#                           davor gesourct (Kontrakt: sourcebar), damit z. B. $PROJECT_ROOT im
#                           Kommando trägt (gleicher Fußgänger + gleiche Kur wie bin/recycle).
#   INBOX_WATCH_ALERT_CMD   Eskalations-Hook (überschreibt den gleichnamigen Prozess-Env-Fallback
#                           unten). Kontrakt: `$ALERT_CMD <uid> <lead> <standup-pfad>`.
#
# Env:
#   DEV_TEAM_REGISTRY       zentrale projects.registry.json (Default wie scut-router.sh)
#   INBOX_WATCH_STATE       State-Dir (Default ~/.claude/inbox-watch)
#   INBOX_WATCH_STALE_MIN   busy gilt nach N Minuten als stale (Default 90)
#   INBOX_WATCH_MAX_NUDGE   max. Re-Nudge-Versuche pro Vorgang, bevor eskaliert wird (Default 3)
#   INBOX_WATCH_ALERT_CMD   Eskalations-Hook, Fallback wenn dev-team.env keinen setzt (Unit-Env,
#                           gilt dann für alle Projekte ohne eigenen). Optional — ohne Alert-Cmd
#                           wird nur laut geloggt (siehe Punkt 5).
#   INBOX_WATCH_BOOT        1 = Lead bei Session-down via mux_boot wecken (Default 0)
#   INBOX_WATCH_DRYRUN      1 = keine mux-Aufrufe (Nudge/Re-Nudge gelten als versucht); Pending-
#                           State + Verifikation laufen normal weiter (deterministisch testbar)
#
# Exit immer 0 (Monitoring, kein Gate). Host-Verdrahtung (Timer/Enable) = Instanz + {HUMAN} (T4).
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENGINE_ROOT="${ENGINE_ROOT:-$(cd "$DIR/.." && pwd)}"
TOOLHUB="$(cd "$ENGINE_ROOT/.." && pwd)"
REGISTRY="${DEV_TEAM_REGISTRY:-$TOOLHUB/projects.registry.json}"
STATE_DIR="${INBOX_WATCH_STATE:-$HOME/.claude/inbox-watch}"
STALE_MIN="${INBOX_WATCH_STALE_MIN:-90}"
MAX_NUDGE="${INBOX_WATCH_MAX_NUDGE:-3}"
ALERT_CMD_DEFAULT="${INBOX_WATCH_ALERT_CMD:-}"
DO_BOOT="${INBOX_WATCH_BOOT:-0}"
DRYRUN="${INBOX_WATCH_DRYRUN:-0}"
. "$DIR/lib/boot.sh"   # liefert mux_boot + (via mux.sh) mux_has/mux_send/mux_flush_draft

mkdir -p "$STATE_DIR"

# Single-Instance-Guard (0.14.0-Gate, Riker-Fund): Timer-/Cron-Overlap darf die
# "genau-einmal"-Eskalation nicht verletzen können (Pattern aus bridge-receive.sh). Läuft
# bereits eine Instanz, wird dieser Durchlauf sauber übersprungen — exit 0, kein State-Touch.
exec 9>"$STATE_DIR/.lock"
flock -n 9 || { echo "[inbox-watch] Lauf übersprungen (eine andere Instanz läuft bereits)"; exit 0; }

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
  # Unparsbarer Timestamp → als STALE behandeln (age=99999): ein kaputter Heartbeat darf
  # den Nudge nicht ewig unterdrücken (busy-frisch wäre die falsche Default-Annahme).
  local es now age=99999
  es="$(date -d "$ts" +%s 2>/dev/null || echo 0)"; now="$(date +%s)"
  [ "$es" -gt 0 ] && age=$(( (now-es)/60 ))
  printf '%s:%s' "${st:-none}" "$age"
}

# log_line_count <log> -> Zeilenzahl (0 wenn Datei fehlt).
log_line_count() { [ -f "$1" ] && wc -l < "$1" | tr -d ' ' || printf '0'; }

# heartbeat_since <log> <lines_at_nudge> -> true wenn seither eine NEUE Zeile angehängt wurde.
heartbeat_since() {
  local now_lines; now_lines="$(log_line_count "$1")"
  [ "$now_lines" -gt "$2" ]
}

# watch_sig <standup> — Signatur "größe:anzahl:queue" von _inbox.md + _inbox/ + _review-queue.md
# (die Review-Queue ist ein Eingang wie jeder andere — ungerichtete Router-Mails landen dort
#  und dürfen nicht unbemerkt liegen; Fleet-Fund 2026-07-05: Kundenmail lag ~14h ungesehen).
watch_sig() {
  local sd="$1" size=0 cnt=0 q=0
  [ -f "$sd/_inbox.md" ] && size="$(wc -c < "$sd/_inbox.md" | tr -d ' ')"
  [ -d "$sd/_inbox" ] && cnt="$(find "$sd/_inbox" -type f 2>/dev/null | wc -l | tr -d ' ')"
  [ -f "$sd/_review-queue.md" ] && q="$(wc -c < "$sd/_review-queue.md" | tr -d ' ')"
  printf '%s:%s:%s' "$size" "$cnt" "$q"
}

# state_kind <statef> -> "final" | "pending" | "none"
state_kind() {
  [ -f "$1" ] || { printf 'none'; return; }
  case "$(cat "$1" 2>/dev/null)" in
    PENDING\ *) printf 'pending' ;;
    *) printf 'final' ;;
  esac
}

# state_field <statef> <key> -> Wert aus einer "PENDING sig=... lines=... attempts=..."-Zeile.
state_field() { sed -n "s/.* $2=\([^ ]*\).*/\1/p" "$1" 2>/dev/null | head -n1; }

# is_uint <wert> -> true bei einer nichtleeren Ziffernfolge.
is_uint() { case "$1" in ''|*[!0-9]*) return 1 ;; *) return 0 ;; esac; }

# state_write_final <statef> <sig> -> Alt-Format: nackte Signatur, keine Newline.
state_write_final() { printf '%s' "$2" > "$1"; }

# state_write_pending <statef> <sig> <lines> <attempts>
state_write_pending() { printf 'PENDING sig=%s lines=%s attempts=%s' "$2" "$3" "$4" > "$1"; }

# run_alert <cmd> <uid> <lead> <standup> -> führt INBOX_WATCH_ALERT_CMD mit Kontrakt-Args aus.
run_alert() {
  local cmd="$1" uid="$2" lead="$3" standup="$4"
  bash -c "$cmd"' "$@"' bash "$uid" "$lead" "$standup" >/dev/null 2>&1
}

# escalate_or_swallow <statef> <sig> <uid> <lead> <standup> <alert_cmd> <reason>
# Eskaliert GENAU EINMAL (falls alert_cmd gesetzt) oder verschluckt laut; finalisiert IMMER auf
# <sig>. Setzt _ESC_RESULT=escalated|alert_failed|swallowed für den Aufrufer (Summary-Zähler) —
# ein FEHLGESCHLAGENER Alert-Cmd zählt bewusst NICHT als "eskaliert" mit (0.14.0-Gate,
# Riker-Fund: sonst würde ein kaputter Alert-Cmd sich als Erfolg tarnen).
escalate_or_swallow() {
  local statef="$1" sig="$2" uid="$3" lead="$4" standup="$5" alert_cmd="$6" reason="$7"
  if [ -n "$alert_cmd" ]; then
    if run_alert "$alert_cmd" "$uid" "$lead" "$standup"; then
      echo "[inbox-watch] $uid: $reason — ESKALIERT → $alert_cmd"
      _ESC_RESULT=escalated
    else
      echo "[inbox-watch] $uid: $reason — Eskalation an $alert_cmd FEHLGESCHLAGEN"
      _ESC_RESULT=alert_failed
    fi
  else
    echo "[inbox-watch] $uid: $reason — VERSCHLUCKT (kein INBOX_WATCH_ALERT_CMD konfiguriert)"
    _ESC_RESULT=swallowed
  fi
  state_write_final "$statef" "$sig"
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

n_new=0; n_nudge=0; n_escalated=0; n_alert_failed=0; n_swallowed=0

# esc_count <_ESC_RESULT> -> passenden Summary-Zähler hochzählen (escalated|alert_failed|swallowed).
esc_count() {
  case "$1" in
    escalated)    n_escalated=$((n_escalated+1)) ;;
    alert_failed) n_alert_failed=$((n_alert_failed+1)) ;;
    *)            n_swallowed=$((n_swallowed+1)) ;;
  esac
}
while IFS=$'\t' read -r uid path standup; do
  [ -z "$uid" ] && continue
  standup="$(expand_tilde "$standup")"; path="$(expand_tilde "$path")"
  [ -f "$standup/_inbox.md" ] || { echo "[inbox-watch] $uid: keine _inbox.md — skip"; continue; }

  sig="$(watch_sig "$standup")"
  statef="$STATE_DIR/$uid.state"
  envf="$path/_dev_team/dev-team.env"
  lead="$(env_of "$envf" TEAM_LEAD)"; lead="${lead:-Bob}"
  session="$(env_of "$envf" MUX_SESSION)"
  alert_cmd="$(env_of "$envf" INBOX_WATCH_ALERT_CMD)"; alert_cmd="${alert_cmd:-$ALERT_CMD_DEFAULT}"
  leadlog="$standup/$lead.log"

  kind="$(state_kind "$statef")"
  attempts=0   # Versuche für die AKTUELL zu behandelnde Signatur (0 = frischer Zyklus)

  if [ "$kind" = pending ]; then
    psig="$(state_field "$statef" sig)"
    plines_raw="$(state_field "$statef" lines)"
    patt_raw="$(state_field "$statef" attempts)"

    if [ -z "$psig" ] || ! is_uint "$plines_raw" || ! is_uint "$patt_raw"; then
      # 0.14.0-Gate, Marvin-Fund: ein fehlendes Pflichtfeld NICHT permissiv defaulten (ein
      # defaultes lines=0 hätte fast jeden Heartbeat sofort als Zustellnachweis durchgehen
      # lassen) — konservativ wie "kein State" behandeln, frischer Zyklus.
      echo "[inbox-watch] $uid: PENDING-State korrupt (Pflichtfeld fehlt/ungültig) — als frischer Zyklus behandelt"
    else
      plines="$plines_raw"; patt="$patt_raw"
      if heartbeat_since "$leadlog" "$plines"; then
        echo "[inbox-watch] $uid: Nudge verifiziert — Lead $lead heartbeatete seither ($patt Versuch(e))"
        state_write_final "$statef" "$psig"
        if [ "$sig" = "$psig" ]; then
          continue
        fi
        # Signatur ist seit dem Nudge weitergewandert -> unten als frischer Zyklus behandelt.
      elif [ "$sig" = "$psig" ]; then
        attempts="$patt"
      else
        echo "[inbox-watch] $uid: weitere Eingänge, alter Nudge an $lead noch unverifiziert — neuer Zyklus"
      fi
    fi
  elif [ "$kind" = final ]; then
    old="$(cat "$statef" 2>/dev/null || echo "")"
    if [ "$sig" = "$old" ]; then
      echo "[inbox-watch] $uid: ok (unverändert)"
      continue
    fi
  fi

  n_new=$((n_new+1))

  st_age="$(lead_state "$leadlog")"
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
    escalate_or_swallow "$statef" "$sig" "$uid" "$lead" "$standup" "$alert_cmd" \
      "NEU, Lead $lead=$st, kein Weckweg (kein MUX_SESSION konfiguriert)"
    esc_count "$_ESC_RESULT"
    continue
  fi

  if [ "$attempts" -ge "$MAX_NUDGE" ]; then
    escalate_or_swallow "$statef" "$sig" "$uid" "$lead" "$standup" "$alert_cmd" \
      "$attempts Nudge-Versuch(e) erschöpft (Limit $MAX_NUDGE), Lead $lead nicht verifiziert"
    esc_count "$_ESC_RESULT"
    continue
  fi

  next_attempt=$((attempts+1))
  text="📬 [$uid] Neue Eingänge — bitte $standup/_inbox.md (+ _review-queue.md) lesen."
  lines_before="$(log_line_count "$leadlog")"

  if [ "$next_attempt" -ge 2 ] && [ "$DRYRUN" != 1 ]; then
    mux_flush_draft "$session" 2>/dev/null   # hängenden zellij-Draft vor dem Re-Nudge submitten
  fi

  if [ "$DRYRUN" = 1 ]; then
    echo "[inbox-watch] $uid: NUDGE #$next_attempt → $session (dryrun, Lead $lead war $st) — wartet auf Heartbeat-Verifikation"
    state_write_pending "$statef" "$sig" "$lines_before" "$next_attempt"
    n_nudge=$((n_nudge+1))
    continue
  fi

  if mux_has "$session" 2>/dev/null; then
    if mux_send "$session" "$text" 2>/dev/null; then
      echo "[inbox-watch] $uid: NUDGE #$next_attempt → $session (Lead $lead war $st) — wartet auf Heartbeat-Verifikation"
      state_write_pending "$statef" "$sig" "$lines_before" "$next_attempt"
      n_nudge=$((n_nudge+1))
    else
      echo "[inbox-watch] $uid: NUDGE #$next_attempt an $session fehlgeschlagen — State bleibt offen"
    fi
  else
    if [ "$DO_BOOT" = 1 ]; then
      boot_cmd="$(env_of "$envf" BOOT_CMD)"
      # BOOT_CMD läuft in einer FRISCHEN Shell (mux_spawn) — dev-team.env vorher sourcen, damit
      # $PROJECT_ROOT & Co. im Kommando tragen (Kontrakt: die Datei ist sourcebar; ein
      # Source-Fehler bricht den Boot nicht ab). Gleicher Fußgänger + gleiche Kur wie bin/recycle.
      start_cmd="{ [ -f $(printf '%q' "$envf") ] && . $(printf '%q' "$envf"); } >/dev/null 2>&1; $boot_cmd"
      if [ -n "$boot_cmd" ] && mux_boot "$session" "$start_cmd" "" >/dev/null 2>&1; then
        echo "[inbox-watch] $uid: Session down → GEBOOTET ($session; liest Inbox beim Start)"
        state_write_final "$statef" "$sig"
        n_nudge=$((n_nudge+1))
      else
        echo "[inbox-watch] $uid: Session down, Boot nicht möglich (BOOT_CMD fehlt/Fehler) — State offen"
      fi
    else
      echo "[inbox-watch] $uid: NEU, aber Session $session down (Boot aus) — State bleibt offen"
    fi
  fi
done <<< "$(projects)"

echo "── inbox-watch: $n_new Projekt(e) mit Neuem, $n_nudge genudged/gebootet, $n_escalated eskaliert, $n_alert_failed Alert-Fehlschlag(e), $n_swallowed ungeweckt-verschluckt (registry=$REGISTRY)"
exit 0
