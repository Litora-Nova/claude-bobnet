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
#   2. State-File pro uid, drei Formen:
#        final:        "FINAL sig=<sig> ilines=<N>" — bekannt/erledigt, N = _inbox.md-Zeilenzahl
#                       zum Zeitpunkt der Finalisierung (Baseline für Self-Write-Erkennung, #56).
#        final-legacy:  nackte Signatur (Alt-Format vor diesem Batch) — weiter gelesen, aber ab
#                       dem nächsten Schreiben auf das neue Format gehoben. Ohne `ilines` ist
#                       Self-Write-Erkennung diesen Zyklus NICHT möglich (konservativ, s. Punkt 7).
#        pending:       "PENDING sig=<sig> lines=<N> attempts=<n> ilines=<M>" — ein Nudge ist
#                       raus, aber NICHT über den mux_send-rc verifiziert. Verifikation läuft
#                       über den Lead-Heartbeat: `<standup>/<TEAM_LEAD>.log` hat seit dem Nudge
#                       eine NEUE Zeile bekommen (aktuelle Zeilenzahl > Snapshot bei Nudge-Zeit) —
#                       Stand-up beginnt kanonisch mit Heartbeat + Inbox lesen, ein neuer
#                       Log-Eintrag gilt also als Zustellnachweis. (Zeilenzahl statt Timestamp:
#                       `log.sh` schreibt nur Minutenauflösung — ein Nudge + Heartbeat in
#                       derselben Minute wäre über Timestamps nicht sauber unterscheidbar.)
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
#                                  Boot gilt als zugestellt) ODER — ohne Boot — GENAU EINMAL pro
#                                  Down-Vorgang eskalieren statt endlos zu loggen (Punkt 10, #55).
#   5. Eskalation (`INBOX_WATCH_ALERT_CMD`, opt-in) läuft GENAU EINMAL pro Vorgang, wenn (a) die
#      Re-Nudge-Versuche erschöpft sind, ohne verifiziert worden zu sein, oder (b) gar kein
#      Weckweg existiert (report-only, kein MUX_SESSION). Ohne Alert-Cmd wird trotzdem finalisiert
#      (kein Endlos-Loop) — aber laut als „VERSCHLUCKT" geloggt + in der Summary-Zeile gezählt.
#      Schlägt der Alert-Cmd selbst fehl (rc≠0), zählt das NICHT als „eskaliert" mit — eigener
#      Zähler „Alert-Fehlschlag(e)" in der Summary-Zeile (0.14.0-Gate, Riker-Fund).
#   6. State fortschreiben NUR bei Nudge (→ pending) oder Verifikation/Eskalation/report-only/
#      Self-Write (→ final) — busy/blocked-Skips + fehlgeschlagene Sends bleiben „offen". Eine
#      korrupte PENDING-Zeile (Pflichtfeld sig/lines/attempts fehlt oder ist nicht numerisch)
#      wird KONSERVATIV wie „kein State" behandelt — frischer Zyklus statt eines permissiven
#      Default (0.14.0-Gate, Marvin-Fund: ein defaultendes `lines=0` hätte fast jeden Heartbeat
#      sofort als Zustellnachweis durchgehen lassen). Dieselbe Konservativität gilt für ein
#      fehlendes `ilines` (Alt-Format) bei der Self-Write-Erkennung (Punkt 7).
#   7. Self-Write-Erkennung (Anti-Lärm-Batch Welle 1, #56 — Feld-Fund 2026-07-10/07-16: Lead-
#      eigene Inbox-Writes bzw. die Antwort auf einen Nudge starten sonst den NÄCHSTEN Zyklus,
#      das erklärt >12-Nudge-Serien bei konstanter „echter" Inhaltslage): jedes State-Write
#      merkt sich zusätzlich `ilines` = _inbox.md-Zeilenzahl zu diesem Zeitpunkt. Wächst
#      _inbox.md seit der letzten bekannten `ilines`-Baseline, werden GENAU die neuen Zeilen
#      geprüft — sind ALLE mit der Lead-Eigensignatur unterschrieben (comms.md-Kanon
#      "Text — (Absender)": Zeile endet auf "— ($TEAM_LEAD" oder "— $TEAM_LEAD", Klammer
#      optional, Emoji/Suffixe danach toleriert), gilt der Zyklus als Self-Write: still auf die
#      aktuelle Signatur finalisiert, KEIN Nudge, KEINE Eskalation. Ist auch nur EINE neue Zeile
#      fremd, läuft der Zyklus normal (Nudge/Eskalation) — nie eine feine Filterung pro Zeile.
#      Reine `_inbox/`- oder Review-Queue-Änderungen sind NIE Self-Write (die schreibt sich
#      niemand selbst in die eigene _inbox.md) und nudgen wie bisher; landen Media-Drop +
#      zugehöriger Mail-Eintrag im selben Tick, ist es ohnehin EIN Zyklus (eine Signatur).
#      Fehlt die `ilines`-Baseline (Alt-Format-State) oder ist gar kein State vorhanden
#      (erster Kontakt), ist Self-Write-Erkennung diesen Zyklus nicht möglich — konservativ wie
#      bisher behandelt (nudgen), heilt sich mit dem nächsten Schreiben selbst.
#      Delta-Gate-Härtung (Riker): der Router-Quell-Marker "SCUT (" (serverseitig von
#      scut-router.sh gestempelt, NICHT vom Absender kontrollierbar) schließt Self-Write IMMER
#      aus — sonst könnte eine extern geroutete Zeile (Kunde/Angreifer), die absichtlich auf
#      "— ($TEAM_LEAD)" endet, den Zyklus lautlos verschlucken (kein Nudge, keine Eskalation,
#      keine Severity-Klassifikation). Jeder Self-Write-Finalize zählt zusätzlich in einen
#      eigenen Summary-Zähler (`self-write-finalisiert`) — damit dieser Pfad nie wieder
#      telemetrielos ist.
#   8. Severity-Klassifikation für jede Eskalation (`urgent|mid|info`, s. `INBOX_WATCH_ALERT_CMD`
#      unten): urgent = die Review-Queue ist gewachsen ODER eine neue fremde Zeile trägt den
#      „SCUT (via "-Marker (Kunden-/Mensch-Kanal, s. scut-router.sh) ODER Session-down; mid =
#      sonstige fremde neue Einträge (Nudges erschöpft/kein Weckweg); info = bekannt harmlose
#      Restfälle (z. B. reiner `_inbox/`-Datei-Churn ohne begleitende _inbox.md-Zeile). Ohne
#      verlässliche Baseline (Alt-Format) wird konservativ `mid` statt `info` klassifiziert.
#      `INBOX_WATCH_ALERT_MIN_SEVERITY` (Default `mid`) filtert: Events darunter werden geloggt,
#      aber NICHT an den Alert-Cmd gereicht — eigener Summary-Zähler „unterhalb-Mindest-
#      Severity", nicht „verschluckt" (das bleibt reserviert für „kein Alert-Cmd konfiguriert").
#   9. Off-Duty-Flag `<standup>/.off-duty` (vom Lead selbst am Feierabend berührt): solange die
#      Datei existiert, werden für dieses Projekt WEDER Nudges NOCH Alerts ausgelöst (auch keine
#      Session-down-Eskalation, Punkt 10) — State bleibt komplett unangetastet, der nächste
#      Stand-up liest die Inbox ohnehin. Auto-Clear: heartbeatet der Lead NACH der mtime des
#      Flags (er ist zurück), löscht der Watcher es selbst — kein manuelles Aufräumen nötig.
#  10. Session-down-Eskalation (#55): ist MUX_SESSION konfiguriert, die Session aber down und
#      INBOX_WATCH_BOOT=0, eskaliert der Watcher GENAU EINMAL pro Down-Vorgang (severity=urgent,
#      source=session-down) statt bei jedem Tick dieselbe Zeile zu loggen. Ein separater
#      Marker (`<STATE_DIR>/<uid>.sessiondown`, unabhängig vom Content-State) hält das fest;
#      kommt die Session zurück (mux_has wieder wahr), wird der Marker gelöscht — die nächste
#      Down-Episode eskaliert wieder frisch. Der Content-State selbst bleibt dabei unberührt
#      (die Inbox wurde ja nicht zugestellt) — nur die Down-Tatsache wird gemeldet.
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
#   TEAM_LEAD              Name, unter dem der Lead heartbeatet (Log-Dateiname) UND die eigene
#                          Signatur für die Self-Write-Erkennung (Punkt 7). Default: Bob.
#   MUX_SESSION             Multiplexer-Session des Leads (für den Nudge). Fehlt → report-only.
#   BOOT_CMD                Start-Kommando des Leads (nur mit INBOX_WATCH_BOOT=1 genutzt). Läuft
#                           in einer FRISCHEN Shell (mux_spawn) — die eigene dev-team.env wird
#                           davor gesourct (Kontrakt: sourcebar), damit z. B. $PROJECT_ROOT im
#                           Kommando trägt (gleicher Fußgänger + gleiche Kur wie bin/recycle).
#   INBOX_WATCH_ALERT_CMD   Eskalations-Hook (überschreibt den gleichnamigen Prozess-Env-Fallback
#                           unten). Kontrakt v2 (additiv zu v1, abwärtskompatibel): `$ALERT_CMD
#                           <uid> <lead> <standup-pfad> <severity>` + Env-Exports
#                           `INBOX_WATCH_REASON` (Klartext-Grund) und `INBOX_WATCH_SOURCE`
#                           (`inbox|review-queue|session-down`). Ein v1-Cmd, der nur die ersten
#                           3 Args liest, funktioniert unverändert weiter.
#
# Off-Duty (Punkt 9, kein Env — Flag-File):
#   `<standup>/.off-duty` anlegen (z. B. `touch`) unterdrückt für dieses Projekt jeden Nudge und
#   jede Eskalation, bis die Datei wieder weg ist (manuell ODER automatisch, sobald der Lead
#   danach wieder heartbeatet).
#
# Env:
#   DEV_TEAM_REGISTRY       zentrale projects.registry.json (Default wie scut-router.sh)
#   INBOX_WATCH_STATE       State-Dir (Default ~/.claude/inbox-watch)
#   INBOX_WATCH_STALE_MIN   busy gilt nach N Minuten als stale (Default 90)
#   INBOX_WATCH_MAX_NUDGE   max. Re-Nudge-Versuche pro Vorgang, bevor eskaliert wird (Default 3)
#   INBOX_WATCH_ALERT_CMD   Eskalations-Hook, Fallback wenn dev-team.env keinen setzt (Unit-Env,
#                           gilt dann für alle Projekte ohne eigenen). Optional — ohne Alert-Cmd
#                           wird nur laut geloggt (siehe Punkt 5). Kontrakt siehe oben.
#   INBOX_WATCH_ALERT_MIN_SEVERITY   Mindest-Severity, ab der der Alert-Cmd überhaupt gerufen
#                           wird (`info`|`mid`|`urgent`, Default `mid`) — s. Punkt 8.
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
MIN_SEVERITY="${INBOX_WATCH_ALERT_MIN_SEVERITY:-mid}"
DO_BOOT="${INBOX_WATCH_BOOT:-0}"
DRYRUN="${INBOX_WATCH_DRYRUN:-0}"
. "$DIR/lib/boot.sh"      # liefert mux_boot + (via mux.sh) mux_has/mux_send/mux_flush_draft
. "$DIR/lib/standup.sh"   # liefert expand_tilde/lead_state/log_line_count/heartbeat_since (mit bin/recycle geteilt)

mkdir -p "$STATE_DIR"

# Single-Instance-Guard (0.14.0-Gate, Riker-Fund): Timer-/Cron-Overlap darf die
# "genau-einmal"-Eskalation nicht verletzen können (Pattern aus bridge-receive.sh). Läuft
# bereits eine Instanz, wird dieser Durchlauf sauber übersprungen — exit 0, kein State-Touch.
exec 9>"$STATE_DIR/.lock"
flock -n 9 || { echo "[inbox-watch] Lauf übersprungen (eine andere Instanz läuft bereits)"; exit 0; }

# env_of <envfile> <key> — export KEY="wert" / export KEY=wert lesen (leer wenn fehlt).
env_of() { [ -f "$1" ] && sed -n "s/^export $2=\"\{0,1\}\([^\"]*\)\"\{0,1\}.*/\1/p" "$1" | head -n1; }

# last_heartbeat_epoch <log> -> Unix-Epoch der letzten Heartbeat-Zeile (0 wenn fehlt/unparsbar).
# Eigenständig statt über lead_state() (liefert nur Alter in Minuten) — Off-Duty-Auto-Clear
# (Punkt 9) braucht den absoluten Zeitpunkt, um ihn gegen die Flag-mtime zu vergleichen.
last_heartbeat_epoch() {
  local log="$1"
  [ -f "$log" ] || { printf '0'; return; }
  local last ts es
  last="$(tail -n1 "$log")"
  ts="$(printf '%s' "$last" | cut -d'|' -f1 | sed 's/[[:space:]]*$//')"
  es="$(date -d "$ts" +%s 2>/dev/null || echo 0)"
  printf '%s' "$es"
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

# sig_field <sig> <n> -> n-tes Feld (1-basiert) einer "größe:anzahl:queue"-Signatur, "0" wenn
# leer/fehlend (leere/korrupte Signatur darf die Severity-Klassifikation nicht crashen).
sig_field() {
  local s="$1" n="$2" IFS=:
  local -a parts
  read -ra parts <<< "$s"
  printf '%s' "${parts[$((n-1))]:-0}"
}

# state_kind <statef> -> "final" | "final-legacy" | "pending" | "none"
state_kind() {
  [ -f "$1" ] || { printf 'none'; return; }
  case "$(cat "$1" 2>/dev/null)" in
    PENDING\ *) printf 'pending' ;;
    FINAL\ *)   printf 'final' ;;
    *)          printf 'final-legacy' ;;   # Alt-Format: nackte Signatur, kein ilines
  esac
}

# state_field <statef> <key> -> Wert aus einer "... key=wert ..."-Zeile (PENDING oder FINAL).
state_field() { sed -n "s/.* $2=\([^ ]*\).*/\1/p" "$1" 2>/dev/null | head -n1; }

# is_uint <wert> -> true bei einer nichtleeren Ziffernfolge.
is_uint() { case "$1" in ''|*[!0-9]*) return 1 ;; *) return 0 ;; esac; }

# state_write_final <statef> <sig> <ilines>
state_write_final() { printf 'FINAL sig=%s ilines=%s' "$2" "$3" > "$1"; }

# state_write_pending <statef> <sig> <lines> <attempts> <ilines>
state_write_pending() { printf 'PENDING sig=%s lines=%s attempts=%s ilines=%s' "$2" "$3" "$4" "$5" > "$1"; }

# self_write_line <line> <lead> -> true, wenn die Zeile mit der Lead-Eigensignatur endet
# (comms.md-Kanon "Text — (Absender)": "— ($lead" oder "— $lead", Klammer optional). Toleranz-
# fenster = die letzten 48 Zeichen der Zeile, damit ein Emoji/Satzzeichen NACH der Signatur
# (z. B. "— (Bob) 🐻") nicht durchfällt — ein zufälliges "— (Bob)" mitten im Fließtext einer
# LANGEN fremden Zeile zählt damit bewusst nicht als Signatur.
#
# Delta-Gate-Fund (Riker): das Suffix ist reiner Freitext — eine extern geroutete Zeile
# (Kunde/Angreifer) kann absichtlich auf "— ($lead)" enden und würde sonst lautlos als
# Self-Write finalisiert (kein Nudge, keine Eskalation, kein Summary-Zähler — umginge sogar
# den SCUT-urgent-Zwang, weil Self-Write VOR classify_severity läuft). Fix: der Router-
# Quell-Marker "SCUT (" (von scut-router.sh SERVERSEITIG gestempelt, s. dessen `route_event` —
# NICHT vom Absender kontrollierbar) schließt Self-Write IMMER aus, egal was das Suffix
# behauptet. Nur eine Zeile OHNE diesen Marker kann Self-Write sein.
self_write_line() {
  local line="$1" lead="$2"
  [ -n "$lead" ] || return 1
  case "$line" in
    *"SCUT ("*) return 1 ;;
  esac
  # ${line: -48} bei einer KÜRZEREN Zeile als 48 Zeichen liefert in bash leer statt der ganzen
  # Zeile (Offset-Quirk, kein Trunkierungs-Bug) — deshalb erst die Länge prüfen.
  local tail="$line"
  [ "${#line}" -gt 48 ] && tail="${line: -48}"
  case "$tail" in
    *"— ($lead"*|*"—($lead"*|*"— $lead"*) return 0 ;;
    *) return 1 ;;
  esac
}

# sev_rank <info|mid|urgent> -> numerischer Rang (Unbekanntes -> mid, konservative Mitte).
sev_rank() { case "$1" in info) printf 0 ;; urgent) printf 2 ;; *) printf 1 ;; esac; }
# severity_ge <sev> <min> -> true, wenn <sev> mindestens so hoch ist wie <min>.
severity_ge() { [ "$(sev_rank "$1")" -ge "$(sev_rank "$2")" ]; }

# classify_severity <old_sig> <new_sig> <new_foreign_lines> <have_baseline 0|1> -> info|mid|urgent
# (Punkt 8): Review-Queue gewachsen ODER "SCUT (via "-Marker unter den neuen Zeilen -> urgent;
# sonst irgendeine bekannte neue Zeile -> mid; nichts Textuelles Neues (bestätigt per Baseline,
# z. B. reiner _inbox/-Datei-Churn) -> info; keine Baseline verfügbar -> konservativ mid.
classify_severity() {
  local old="$1" new="$2" lines="$3" have_baseline="$4" oq nq
  oq="$(sig_field "$old" 3)"; is_uint "$oq" || oq=0
  nq="$(sig_field "$new" 3)"; is_uint "$nq" || nq=0
  if [ "$nq" -gt "$oq" ]; then printf 'urgent'; return; fi
  if [ -n "$lines" ] && printf '%s\n' "$lines" | grep -q 'SCUT (via '; then printf 'urgent'; return; fi
  if [ -n "$lines" ]; then printf 'mid'; return; fi
  [ "$have_baseline" = 1 ] && { printf 'info'; return; }
  printf 'mid'
}

# classify_source <old_sig> <new_sig> -> "review-queue" | "inbox" (Env INBOX_WATCH_SOURCE für
# den Alert-Cmd, Punkt 8) — "session-down" wird an dessen eigener Aufrufstelle direkt gesetzt.
classify_source() {
  local old="$1" new="$2" oq nq
  oq="$(sig_field "$old" 3)"; is_uint "$oq" || oq=0
  nq="$(sig_field "$new" 3)"; is_uint "$nq" || nq=0
  [ "$nq" -gt "$oq" ] && { printf 'review-queue'; return; }
  printf 'inbox'
}

# run_alert <cmd> <uid> <lead> <standup> <severity> <reason> <source> -> führt INBOX_WATCH_ALERT_CMD
# mit Kontrakt v2 aus (additiv zu v1 — ein Cmd, der nur die ersten 3 Args liest, bleibt unberührt).
run_alert() {
  local cmd="$1" uid="$2" lead="$3" standup="$4" severity="$5" reason="$6" source="$7"
  INBOX_WATCH_REASON="$reason" INBOX_WATCH_SOURCE="$source" \
    bash -c "$cmd"' "$@"' bash "$uid" "$lead" "$standup" "$severity" >/dev/null 2>&1
}

# run_severity_alert <alert_cmd> <uid> <lead> <standup> <severity> <reason> <source>
# -> _ESC_RESULT=escalated|alert_failed|swallowed|gated. Rührt KEINEN Content-State an — das ist
# Sache des Aufrufers (Content-State- und Session-down-Marker haben unterschiedliche Semantik,
# Punkt 10: ein Session-down-Fund darf die Inbox NICHT als "zugestellt" markieren).
run_severity_alert() {
  local alert_cmd="$1" uid="$2" lead="$3" standup="$4" severity="$5" reason="$6" source="$7"
  if [ -z "$alert_cmd" ]; then
    echo "[inbox-watch] $uid: $reason — VERSCHLUCKT (kein INBOX_WATCH_ALERT_CMD konfiguriert) [severity=$severity]"
    _ESC_RESULT=swallowed
    return
  fi
  if ! severity_ge "$severity" "$MIN_SEVERITY"; then
    echo "[inbox-watch] $uid: $reason — unterhalb Mindest-Severity ($severity < $MIN_SEVERITY), NICHT alarmiert (geloggt)"
    _ESC_RESULT=gated
    return
  fi
  if run_alert "$alert_cmd" "$uid" "$lead" "$standup" "$severity" "$reason" "$source"; then
    echo "[inbox-watch] $uid: $reason — ESKALIERT ($severity) → $alert_cmd"
    _ESC_RESULT=escalated
  else
    echo "[inbox-watch] $uid: $reason — Eskalation an $alert_cmd FEHLGESCHLAGEN"
    _ESC_RESULT=alert_failed
  fi
}

# escalate_or_swallow <statef> <sig> <uid> <lead> <standup> <alert_cmd> <reason> <severity> <source> <ilines>
# Wie run_severity_alert, schreibt danach IMMER den Content-State final (Zustellung DIESES
# Vorgangs gilt als abgeschlossen — Eskalation oder lautes Verschlucken ist die Abschluss-Handlung).
escalate_or_swallow() {
  local statef="$1" sig="$2" uid="$3" lead="$4" standup="$5" alert_cmd="$6" reason="$7" severity="$8" source="$9" ilines="${10}"
  run_severity_alert "$alert_cmd" "$uid" "$lead" "$standup" "$severity" "$reason" "$source"
  state_write_final "$statef" "$sig" "$ilines"
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

n_new=0; n_nudge=0; n_escalated=0; n_alert_failed=0; n_gated=0; n_swallowed=0; n_selfwrite=0

# esc_count <_ESC_RESULT> -> passenden Summary-Zähler hochzählen (escalated|alert_failed|gated|swallowed).
esc_count() {
  case "$1" in
    escalated)    n_escalated=$((n_escalated+1)) ;;
    alert_failed) n_alert_failed=$((n_alert_failed+1)) ;;
    gated)        n_gated=$((n_gated+1)) ;;
    *)            n_swallowed=$((n_swallowed+1)) ;;
  esac
}
while IFS=$'\t' read -r uid path standup; do
  [ -z "$uid" ] && continue
  standup="$(expand_tilde "$standup")"; path="$(expand_tilde "$path")"
  [ -f "$standup/_inbox.md" ] || { echo "[inbox-watch] $uid: keine _inbox.md — skip"; continue; }

  statef="$STATE_DIR/$uid.state"
  envf="$path/_dev_team/dev-team.env"
  lead="$(env_of "$envf" TEAM_LEAD)"; lead="${lead:-Bob}"
  session="$(env_of "$envf" MUX_SESSION)"
  alert_cmd="$(env_of "$envf" INBOX_WATCH_ALERT_CMD)"; alert_cmd="${alert_cmd:-$ALERT_CMD_DEFAULT}"
  leadlog="$standup/$lead.log"
  sessiondown_marker="$STATE_DIR/$uid.sessiondown"

  # Session-down-Reset (Punkt 10, #55): kommt die Session zurück, Marker weg — die nächste
  # Down-Episode eskaliert wieder frisch. Unabhängig von Off-Duty/Inbox-Signatur, jeden Tick
  # geprüft, aber billig (mux_has nur, wenn überhaupt ein Marker existiert).
  if [ -n "$session" ] && [ -f "$sessiondown_marker" ] && mux_has "$session" 2>/dev/null; then
    rm -f "$sessiondown_marker"
    echo "[inbox-watch] $uid: Session $session wieder da — Down-Eskalation zurückgesetzt"
  fi

  # Off-Duty (Punkt 9): Lead hat Feierabend markiert — keine Nudges, keine Alerts (auch keine
  # Session-down-Eskalation, s. u.). State bleibt IMMER offen (kein Statef-Touch) — der nächste
  # Stand-up liest die Inbox ohnehin. Auto-Clear: heartbeatet der Lead NACH der Flag-mtime
  # (er ist zurück), wird das Flag selbst gelöscht.
  offduty="$standup/.off-duty"
  if [ -f "$offduty" ]; then
    flag_epoch="$(date -r "$offduty" +%s 2>/dev/null || echo 0)"
    hb_epoch="$(last_heartbeat_epoch "$leadlog")"
    if [ "$hb_epoch" -gt "$flag_epoch" ] 2>/dev/null; then
      rm -f "$offduty"
      echo "[inbox-watch] $uid: Off-Duty-Flag gelöscht (Lead $lead heartbeatete danach — zurück)"
    else
      echo "[inbox-watch] $uid: Off-Duty ($offduty) — Nudges/Alerts unterdrückt, State bleibt offen"
      continue
    fi
  fi

  sig="$(watch_sig "$standup")"
  cur_ilines="$(log_line_count "$standup/_inbox.md")"
  kind="$(state_kind "$statef")"
  attempts=0        # Versuche für die AKTUELL zu behandelnde Signatur (0 = frischer Zyklus)
  prev_ilines=""     # ilines-Baseline VOR diesem Zyklus (leer = nicht verfügbar/Alt-Format)
  old_sig=""         # letzte bekannte Signatur (für Review-Queue-Delta/Severity)

  if [ "$kind" = pending ]; then
    psig="$(state_field "$statef" sig)"
    plines_raw="$(state_field "$statef" lines)"
    patt_raw="$(state_field "$statef" attempts)"
    pilines_raw="$(state_field "$statef" ilines)"

    if [ -z "$psig" ] || ! is_uint "$plines_raw" || ! is_uint "$patt_raw"; then
      # 0.14.0-Gate, Marvin-Fund: ein fehlendes Pflichtfeld NICHT permissiv defaulten (ein
      # defaultes lines=0 hätte fast jeden Heartbeat sofort als Zustellnachweis durchgehen
      # lassen) — konservativ wie "kein State" behandeln, frischer Zyklus.
      echo "[inbox-watch] $uid: PENDING-State korrupt (Pflichtfeld fehlt/ungültig) — als frischer Zyklus behandelt"
    else
      plines="$plines_raw"; patt="$patt_raw"
      is_uint "$pilines_raw" && prev_ilines="$pilines_raw"
      old_sig="$psig"
      if heartbeat_since "$leadlog" "$plines"; then
        echo "[inbox-watch] $uid: Nudge verifiziert — Lead $lead heartbeatete seither ($patt Versuch(e))"
        # cur_ilines statt der PENDING-Baseline: verifiziert markiert "jetzt vollständig
        # abgearbeitet bis hierhin" — die (stabile, seit Zyklusbeginn unveränderte)
        # Pending-Baseline bleibt Sache der Klassifikation weiter unten, nicht des Final-Writes.
        state_write_final "$statef" "$psig" "$cur_ilines"
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
    fsig="$(state_field "$statef" sig)"
    filines_raw="$(state_field "$statef" ilines)"
    is_uint "$filines_raw" && prev_ilines="$filines_raw"
    old_sig="$fsig"
    if [ "$sig" = "$fsig" ]; then
      echo "[inbox-watch] $uid: ok (unverändert)"
      continue
    fi
  elif [ "$kind" = final-legacy ]; then
    old="$(cat "$statef" 2>/dev/null || echo "")"
    old_sig="$old"
    if [ "$sig" = "$old" ]; then
      echo "[inbox-watch] $uid: ok (unverändert)"
      continue
    fi
    # Alt-Format ohne ilines: prev_ilines bleibt leer -> Self-Write-Erkennung diesen Zyklus
    # bewusst nicht möglich (konservativ, wie bisher) — heilt sich mit dem nächsten State-Write.
  fi

  # Self-Write-Erkennung (Punkt 7, #56): NUR wenn eine gültige ilines-Baseline vorliegt UND
  # _inbox.md selbst gewachsen ist (reine _inbox/- oder Review-Queue-Änderungen sind NIE
  # Self-Write). Sind ALLE neuen Zeilen mit der Lead-Signatur unterschrieben, still finalisieren.
  new_inbox_lines=""
  if is_uint "$prev_ilines" && [ "$cur_ilines" -gt "$prev_ilines" ]; then
    new_inbox_lines="$(tail -n "+$((prev_ilines+1))" "$standup/_inbox.md" 2>/dev/null)"
    all_self=1
    while IFS= read -r nl || [ -n "$nl" ]; do
      [ -z "$nl" ] && continue
      self_write_line "$nl" "$lead" || { all_self=0; break; }
    done <<< "$new_inbox_lines"
    if [ "$all_self" = 1 ]; then
      echo "[inbox-watch] $uid: neue Zeile(n) sind Lead-Eigenschrift (Signatur — ($lead)) — self-write, still finalisiert"
      state_write_final "$statef" "$sig" "$cur_ilines"
      n_selfwrite=$((n_selfwrite+1))
      continue
    fi
  fi

  # baseline_ilines: die STABILE Baseline, aus der dieser Zyklus entstand (letzte final
  # bekannte ilines) — bleibt über ALLE Re-Nudges dieses Zyklus unverändert (sonst würde jeder
  # Re-Nudge die Baseline auf den aktuellen Stand hochziehen und Self-Write-/Severity-Prüfungen
  # des NÄCHSTEN Re-Nudge-Ticks fälschlich "nichts Neues" sehen lassen — im ersten Entwurf dieses
  # Batches per Spec-Lauf gefunden + gefixt, s. Testfälle (l)/(m)). Ohne bekannte Baseline
  # (erster Kontakt/Alt-Format) fällt sie auf cur_ilines zurück (neue Baseline ab jetzt, konservativ).
  baseline_ilines="${prev_ilines:-$cur_ilines}"

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

  have_baseline=0; is_uint "$prev_ilines" && have_baseline=1
  severity="$(classify_severity "$old_sig" "$sig" "$new_inbox_lines" "$have_baseline")"
  source_="$(classify_source "$old_sig" "$sig")"

  if [ -z "$session" ]; then
    escalate_or_swallow "$statef" "$sig" "$uid" "$lead" "$standup" "$alert_cmd" \
      "NEU, Lead $lead=$st, kein Weckweg (kein MUX_SESSION konfiguriert)" "$severity" "$source_" "$cur_ilines"
    esc_count "$_ESC_RESULT"
    continue
  fi

  if [ "$attempts" -ge "$MAX_NUDGE" ]; then
    escalate_or_swallow "$statef" "$sig" "$uid" "$lead" "$standup" "$alert_cmd" \
      "$attempts Nudge-Versuch(e) erschöpft (Limit $MAX_NUDGE), Lead $lead nicht verifiziert" "$severity" "$source_" "$cur_ilines"
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
    state_write_pending "$statef" "$sig" "$lines_before" "$next_attempt" "$baseline_ilines"
    n_nudge=$((n_nudge+1))
    continue
  fi

  if mux_has "$session" 2>/dev/null; then
    if mux_send "$session" "$text" 2>/dev/null; then
      echo "[inbox-watch] $uid: NUDGE #$next_attempt → $session (Lead $lead war $st) — wartet auf Heartbeat-Verifikation"
      state_write_pending "$statef" "$sig" "$lines_before" "$next_attempt" "$baseline_ilines"
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
        state_write_final "$statef" "$sig" "$cur_ilines"
        n_nudge=$((n_nudge+1))
      else
        echo "[inbox-watch] $uid: Session down, Boot nicht möglich (BOOT_CMD fehlt/Fehler) — State offen"
      fi
    else
      # Punkt 10, #55: Session down + kein Boot -> GENAU EINMAL pro Down-Vorgang eskalieren
      # (severity=urgent, source=session-down), statt bei jedem Tick dieselbe Zeile zu loggen.
      # Der Content-State bleibt ABSICHTLICH unangetastet — die Inbox wurde ja nicht zugestellt.
      if [ -f "$sessiondown_marker" ]; then
        echo "[inbox-watch] $uid: Session $session weiterhin down (Boot aus) — bereits eskaliert, State bleibt offen"
      else
        : > "$sessiondown_marker"
        run_severity_alert "$alert_cmd" "$uid" "$lead" "$standup" urgent \
          "Session $session down, kein Boot (INBOX_WATCH_BOOT=0) — Inbox bleibt ungesehen" session-down
        esc_count "$_ESC_RESULT"
        echo "[inbox-watch] $uid: NEU, aber Session $session down (Boot aus) — State bleibt offen (Down-Eskalation: $_ESC_RESULT)"
      fi
    fi
  fi
done <<< "$(projects)"

echo "── inbox-watch: $n_new Projekt(e) mit Neuem, $n_nudge genudged/gebootet, $n_escalated eskaliert, $n_alert_failed Alert-Fehlschlag(e), $n_gated unterhalb-Mindest-Severity, $n_swallowed ungeweckt-verschluckt, $n_selfwrite self-write-finalisiert (registry=$REGISTRY)"
exit 0
