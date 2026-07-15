#!/usr/bin/env bash
# tests/inbox_watch_spec.sh — scripts/inbox-watch.sh (Watcher-Entscheidungslogik, Dry-Run ohne mux).
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN="$HERE/../scripts/inbox-watch.sh"
pass=0; fail=0
t(){ local d="$1" exp="$2" got="$3"; if [ "$got" = "$exp" ]; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL: $d — erwartet '$exp', bekam '$got'"; fi; }
ok(){ local d="$1"; shift; if "$@" >/dev/null 2>&1; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL: $d"; fi; }

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
ok "bash -n sauber" bash -n "$BIN"

mkdir -p "$tmp/alpha/_dev_team/standup" "$tmp/beta/_dev_team/standup" "$tmp/state"
cat > "$tmp/registry.json" <<JSON
{ "version":1, "projects":[
  {"uid":"alpha","name":"alpha","path":"$tmp/alpha","standup":"$tmp/alpha/_dev_team/standup","status":"active"},
  {"uid":"beta","name":"beta","path":"$tmp/beta","standup":"$tmp/beta/_dev_team/standup","status":"active"},
  {"uid":"leer","name":"leer","path":"$tmp/leer","standup":"$tmp/leer","status":"active"},
  {"uid":"delta","name":"delta","path":"$tmp/delta","standup":"$tmp/delta/_dev_team/standup","status":"active"}
]}
JSON
printf 'export TEAM_LEAD="Zed"\nexport MUX_SESSION="alpha_sess"\n' > "$tmp/alpha/_dev_team/dev-team.env"
printf 'export TEAM_LEAD="Yui"\n' > "$tmp/beta/_dev_team/dev-team.env"
# "delta" bleibt bis zum Alt-Format-Test (f) unmaterialisiert (keine _inbox.md -> harmlos "skip").

A="$tmp/alpha/_dev_team/standup"; B="$tmp/beta/_dev_team/standup"
echo "x | @Zed | hallo" > "$A/_inbox.md"
echo "y | @Yui | hallo" > "$B/_inbox.md"
now(){ date '+%Y-%m-%d %H:%M'; }
MAXN=3
run(){ DEV_TEAM_REGISTRY="$tmp/registry.json" INBOX_WATCH_STATE="$tmp/state" INBOX_WATCH_DRYRUN=1 INBOX_WATCH_MAX_NUDGE="$MAXN" bash "$BIN" 2>/dev/null; }

# Lauf 1: alpha-Lead idle → NUDGE #1 (State bleibt PENDING, NICHT sofort finalisiert — Kern von
# #48: der mux_send-rc ist nicht vertrauenswürdig, s. Kopf von inbox-watch.sh) · beta ohne
# MUX_SESSION → kein Weckweg, kein Alert-Cmd konfiguriert → VERSCHLUCKT (laut geloggt, nicht
# still wie vor #48) · leer ohne Inbox → skip
echo "$(now) | idle | warte" > "$A/Zed.log"
echo "$(now) | idle | warte" > "$B/Yui.log"
out="$(run)"; rc=$?
t "exit 0" "0" "$rc"
t "neu + idle → NUDGE #1" "1" "$(printf '%s\n' "$out" | grep -c 'alpha: NUDGE #1 → alpha_sess')"
t "ohne MUX_SESSION, kein Alert-Cmd → VERSCHLUCKT" "1" "$(printf '%s\n' "$out" | grep -c 'beta: NEU.*kein Weckweg.*VERSCHLUCKT')"
t "ohne _inbox.md → skip" "1" "$(printf '%s\n' "$out" | grep -c 'leer: keine _inbox.md')"
t "State nach Nudge = PENDING, nicht final" "PENDING" "$(cut -d' ' -f1 "$tmp/state/alpha.state")"

# (a) Nudge finalisiert NICHT: ohne neuen Heartbeat bleibt die Signatur offen → Re-Nudge #2,
# nicht "ok (unverändert)".
out="$(run)"
t "(a) Nudge finalisiert nicht → Re-Nudge #2 statt ok" "1" "$(printf '%s\n' "$out" | grep -c 'alpha: NUDGE #2 → alpha_sess')"
t "(a) beta unverändert seit VERSCHLUCKT-Finalize → ok" "1" "$(printf '%s\n' "$out" | grep -c 'beta: ok')"

# (b) Heartbeat NACH dem Nudge finalisiert: neue Log-Zeile (kanonisch: Stand-up beginnt mit
# Heartbeat + Inbox lesen) verifiziert den ausstehenden Nudge, ohne dass sich die Inbox geändert
# hat → State wird auf die genudgte Signatur finalisiert, kein weiterer Nudge nötig.
echo "$(now) | idle | zurück" >> "$A/Zed.log"
out="$(run)"
t "(b) Heartbeat verifiziert den Nudge" "1" "$(printf '%s\n' "$out" | grep -c 'alpha: Nudge verifiziert')"
t "(b) keine weitere NUDGE-Zeile im selben Tick" "0" "$(printf '%s\n' "$out" | grep -c 'alpha: NUDGE')"
out="$(run)"
t "(b) danach: ok (unverändert)" "1" "$(printf '%s\n' "$out" | grep -c 'alpha: ok')"

# flock-Single-Instance-Guard (0.14.0-Gate, Riker-Fund): ein überlappender Zweitlauf wird
# sauber übersprungen (exit 0, kein State-Touch), damit ein Timer-/Cron-Overlap die
# "genau-einmal"-Eskalation nicht verletzen kann. Lock im Testprozess selbst halten (fd 8) —
# der Watcher öffnet dieselbe Lock-Datei in einem eigenen Prozess (fd 9) und muss non-blocking
# scheitern. Platziert an einem Punkt, an dem alpha/beta ruhig sind (beide "ok"), damit der
# zusätzliche Lauf nach der Freigabe keine späteren Zyklen verfälscht.
exec 8>"$tmp/state/.lock"
flock -n 8
out="$(run)"
t "flock-Guard: Zweitlauf wird übersprungen" "1" "$(printf '%s\n' "$out" | grep -c 'Lauf übersprungen')"
exec 8>&-
out="$(run)"
t "flock-Guard: nach Freigabe wieder normaler Lauf (alpha weiter ok)" "1" "$(printf '%s\n' "$out" | grep -c 'alpha: ok')"

# busy (frisch) → skip-busy, State bleibt offen → Wiederholungslauf meldet weiter NEU
echo "neuer eintrag" >> "$A/_inbox.md"
echo "$(now) | busy | arbeite" > "$A/Zed.log"
out="$(run)"
t "neu + busy → skip-busy" "1" "$(printf '%s\n' "$out" | grep -c 'alpha: NEU.*skip-busy')"
out="$(run)"
t "busy-Skip hält State offen (re-check)" "1" "$(printf '%s\n' "$out" | grep -c 'alpha: NEU.*skip-busy')"

# Lead wird done → jetzt NUDGE (neuer Zyklus, Versuchszähler bei 1)
echo "$(now) | done | fertig" > "$A/Zed.log"
out="$(run)"
t "done → NUDGE" "1" "$(printf '%s\n' "$out" | grep -c 'alpha: NUDGE #1')"

# stale-busy: alter busy-Heartbeat zählt als idle (Signatur wandert weiter → neuer Zyklus, der
# vorige unverifizierte Nudge bleibt bewusst hinter sich — s. Kopf-Doku Punkt 3)
echo "weiterer eintrag" >> "$A/_inbox.md"
echo "2020-01-01 00:00 | busy | uralt" > "$A/Zed.log"
out="$(run)"
t "stale-busy → NUDGE" "1" "$(printf '%s\n' "$out" | grep -c 'alpha: NUDGE')"

# blocked → skip-blocked (Mensch-Problem, nicht drauflegen)
echo "noch einer" >> "$A/_inbox.md"
echo "$(now) | blocked | warte auf PO" > "$A/Zed.log"
out="$(run)"
t "blocked → skip-blocked" "1" "$(printf '%s\n' "$out" | grep -c 'alpha: NEU.*skip-blocked')"

# kein Lead-Log (none) → nudgen (unbekannt behandeln wir wie idle)
rm "$A/Zed.log"
out="$(run)"
t "kein Heartbeat-Log → NUDGE" "1" "$(printf '%s\n' "$out" | grep -c 'alpha: NUDGE')"

# unparsbarer Timestamp + busy → stale behandeln → NUDGE (kaputter Heartbeat unterdrückt nicht)
echo "kaputter ts eintrag" >> "$A/_inbox.md"
echo "GARBAGE-TS | busy | haengt" > "$A/Zed.log"
out="$(run)"
t "Müll-Timestamp + busy → NUDGE (stale)" "1" "$(printf '%s\n' "$out" | grep -c 'alpha: NUDGE')"

# _inbox/-Dateidrop zählt als Neues (beta weiterhin ohne Alert-Cmd → VERSCHLUCKT)
mkdir -p "$B/_inbox"; echo bild > "$B/_inbox/foto.txt"
echo "$(now) | idle | warte" > "$B/Yui.log"
out="$(run)"
t "_inbox/-Drop → NEU (beta VERSCHLUCKT)" "1" "$(printf '%s\n' "$out" | grep -c 'beta: NEU.*VERSCHLUCKT')"

# Review-Queue-Eintrag zählt als Neues (ungerichtete Router-Mails dürfen nicht liegenbleiben)
echo "x | UNGERICHTET (via email, von kunde) | anfrage" >> "$B/_review-queue.md"
out="$(run)"
t "_review-queue.md → NEU (beta VERSCHLUCKT)" "1" "$(printf '%s\n' "$out" | grep -c 'beta: NEU.*VERSCHLUCKT')"

# (c) Re-Nudge zählt hoch + respektiert INBOX_WATCH_MAX_NUDGE: frischer Zyklus mit Limit 2 —
# #1, #2, dann erschöpft (KEIN #3), ohne Alert-Cmd laut VERSCHLUCKT.
MAXN=2
echo "frischer zyklus für re-nudge-test" >> "$A/_inbox.md"
echo "$(now) | idle | warte" > "$A/Zed.log"
out="$(run)"
t "(c) Re-Nudge #1" "1" "$(printf '%s\n' "$out" | grep -c 'alpha: NUDGE #1')"
out="$(run)"
t "(c) Re-Nudge #2 (Versuchszähler hoch)" "1" "$(printf '%s\n' "$out" | grep -c 'alpha: NUDGE #2')"
out="$(run)"
t "(c) Limit respektiert: kein #3" "0" "$(printf '%s\n' "$out" | grep -c 'alpha: NUDGE #3')"
t "(c) erschöpft ohne Alert-Cmd → VERSCHLUCKT" "1" "$(printf '%s\n' "$out" | grep -c 'alpha:.*erschöpft.*VERSCHLUCKT')"

# (d) Alert-Cmd feuert GENAU EINMAL bei Erschöpfung.
alerts="$tmp/alerts.log"
cat > "$tmp/alert.sh" <<SH
#!/usr/bin/env bash
echo "ALERT uid=\$1 lead=\$2 standup=\$3" >> "$alerts"
SH
chmod +x "$tmp/alert.sh"
printf 'export INBOX_WATCH_ALERT_CMD="%s"\n' "$tmp/alert.sh" >> "$tmp/alpha/_dev_team/dev-team.env"
echo "neuer zyklus mit alert-cmd" >> "$A/_inbox.md"
echo "$(now) | idle | warte" > "$A/Zed.log"
run >/dev/null   # #1
run >/dev/null   # #2 (MAXN=2)
out="$(run)"     # erschöpft → eskalieren
t "(d) erschöpft MIT Alert-Cmd → ESKALIERT" "1" "$(printf '%s\n' "$out" | grep -c 'alpha:.*erschöpft.*ESKALIERT')"
t "(d) Alert-Cmd genau einmal ausgeführt" "1" "$(wc -l < "$alerts" | tr -d ' ')"
out="$(run)"
t "(d) danach finalisiert → ok, kein zweiter Alert" "1" "$(printf '%s\n' "$out" | grep -c 'alpha: ok')"
t "(d) alerts.log wächst nicht weiter" "1" "$(wc -l < "$alerts" | tr -d ' ')"

# (e) report-only + Alert-Cmd feuert (kein MUX_SESSION → kein Re-Nudge-Zyklus, direkt eskaliert).
printf 'export INBOX_WATCH_ALERT_CMD="%s"\n' "$tmp/alert.sh" >> "$tmp/beta/_dev_team/dev-team.env"
echo "beta ohne weckweg, mit alert" >> "$B/_inbox.md"
out="$(run)"
t "(e) report-only MIT Alert-Cmd → ESKALIERT" "1" "$(printf '%s\n' "$out" | grep -c 'beta:.*kein Weckweg.*ESKALIERT')"
t "(e) Alert-Cmd feuert (zweiter Eintrag, uid=beta)" "1" "$(tail -n1 "$alerts" | grep -c 'uid=beta')"
t "(e) alerts.log jetzt 2 Zeilen (alpha + beta)" "2" "$(wc -l < "$alerts" | tr -d ' ')"
out="$(run)"
t "(e) danach finalisiert → ok, kein erneuter Alert" "1" "$(printf '%s\n' "$out" | grep -c 'beta: ok')"
t "(e) alerts.log wächst nicht weiter" "2" "$(wc -l < "$alerts" | tr -d ' ')"

# (f) Alt-Format-State kompatibel: eine vorbestehende nackte Signatur (Format vor #48) wird als
# "final" gelesen — kein Crash, keine Fehlinterpretation als PENDING; danach normale NEU-Erkennung.
mkdir -p "$tmp/delta/_dev_team/standup"
D="$tmp/delta/_dev_team/standup"
printf 'export TEAM_LEAD="Deb"\n' > "$tmp/delta/_dev_team/dev-team.env"
echo "delta eins" > "$D/_inbox.md"
dsig="$(wc -c < "$D/_inbox.md" | tr -d ' '):0:0"
printf '%s' "$dsig" > "$tmp/state/delta.state"
out="$(run)"
t "(f) Alt-Format-State unverändert → ok (kein Crash)" "1" "$(printf '%s\n' "$out" | grep -c 'delta: ok')"
echo "delta zwei" >> "$D/_inbox.md"
echo "$(now) | idle | warte" > "$D/Deb.log"
out="$(run)"
t "(f) Alt-Format-State, geänderte Signatur → normal als NEU erkannt" "1" "$(printf '%s\n' "$out" | grep -c 'delta: NEU')"

# (g) Alert-Fehlschlag getrennt zählen (0.14.0-Gate, Riker-Fund): ein ALERT_CMD, der selbst
# fehlschlägt (rc≠0), darf NICHT als "eskaliert" durchgehen — eigener Zähler + eigene
# Pro-Event-Zeile ("FEHLGESCHLAGEN", nicht "ESKALIERT").
cat > "$tmp/alert_fail.sh" <<'SH'
#!/usr/bin/env bash
exit 1
SH
chmod +x "$tmp/alert_fail.sh"
printf 'export TEAM_LEAD="Yui"\nexport INBOX_WATCH_ALERT_CMD="%s"\n' "$tmp/alert_fail.sh" > "$tmp/beta/_dev_team/dev-team.env"
echo "beta content mit fehlschlagendem alert-cmd" >> "$B/_inbox.md"
out="$(run)"
t "(g) Alert-Fehlschlag NICHT als ESKALIERT gezählt (Pro-Event-Zeile)" "0" "$(printf '%s\n' "$out" | grep -c 'beta:.*ESKALIERT')"
t "(g) Alert-Fehlschlag pro-Event-Zeile FEHLGESCHLAGEN" "1" "$(printf '%s\n' "$out" | grep -c 'beta:.*FEHLGESCHLAGEN')"
t "(g) Summary zählt Alert-Fehlschlag separat (nicht als eskaliert)" "1" "$(printf '%s\n' "$out" | grep -cE '── inbox-watch:.*0 eskaliert, 1 Alert-Fehlschlag')"

# (h) korrupte PENDING-Zeile konservativ (0.14.0-Gate, Marvin-Fund): fehlt ein Pflichtfeld
# (hier: sig), NICHT permissiv mit lines=0 "verifizieren" (das lässt fast jeden Heartbeat sofort
# als Zustellnachweis durchgehen) — stattdessen wie "kein State" behandeln, frischer Zyklus.
echo "$(now) | idle | schon einige zeilen im log" > "$A/Zed.log"
echo "$(now) | idle | noch mehr" >> "$A/Zed.log"
printf 'PENDING lines=0 attempts=1' > "$tmp/state/alpha.state"   # sig fehlt -> korrupt
echo "content für korrupten-pending-test" >> "$A/_inbox.md"
out="$(run)"
t "(h) korrupte PENDING-Zeile NICHT permissiv verifiziert" "0" "$(printf '%s\n' "$out" | grep -c 'alpha: Nudge verifiziert')"
t "(h) korrupte PENDING-Zeile als frischer Zyklus behandelt" "1" "$(printf '%s\n' "$out" | grep -c 'alpha: PENDING-State korrupt')"
t "(h) frischer Zyklus nudgt normal (#1)" "1" "$(printf '%s\n' "$out" | grep -c 'alpha: NUDGE #1')"

# (i)/(j) Boot-Pfad (INBOX_WATCH_BOOT=1): dev-team.env wird vor BOOT_CMD gesourct, weil
# BOOT_CMD in einer FRISCHEN Shell läuft (mux_spawn) — sonst wären $PROJECT_ROOT & Co. dort leer
# (gleicher Fußgänger + gleiche Kur wie bin/recycle f083dd3). Braucht einen echten Multiplexer
# (DRYRUN endet vor dem Boot-Zweig) — Backend fest auf tmux, das liefert auch headless
# zuverlässig zu (zellij ohne attached Client laut mux.sh-Doku nicht).
if command -v tmux >/dev/null 2>&1; then
  boot_marker="$tmp/boot_marker.txt"
  boot_sess="inbox_watch_spec_boot_$$"
  tmux kill-session -t "$boot_sess" >/dev/null 2>&1 || true
  mkdir -p "$tmp/epsilon/_dev_team/standup"
  EP="$tmp/epsilon/_dev_team/standup"
  echo "e | @Deb | hallo" > "$EP/_inbox.md"
  cat > "$tmp/epsilon/_dev_team/dev-team.env" <<ENVEOF
export TEAM_LEAD="Deb"
export MUX_SESSION="$boot_sess"
export PROJECT_ROOT="$tmp/epsilon"
export BOOT_CMD="echo PROJECT_ROOT=\$PROJECT_ROOT >> $boot_marker; sleep 30"
ENVEOF
  python3 - "$tmp/registry.json" "$tmp/epsilon" "$EP" <<'PY'
import json, sys
p, path, standup = sys.argv[1], sys.argv[2], sys.argv[3]
d = json.load(open(p))
d["projects"].append({"uid": "epsilon", "name": "epsilon", "path": path, "standup": standup, "status": "active"})
json.dump(d, open(p, "w"))
PY
  BOBNET_MUX=tmux DEV_TEAM_REGISTRY="$tmp/registry.json" INBOX_WATCH_STATE="$tmp/state" INBOX_WATCH_BOOT=1 bash "$BIN" >/dev/null 2>&1
  sleep 1
  t "(i) BOOT_CMD sieht Env-Werte aus dev-team.env (PROJECT_ROOT nicht leer)" "1" "$(grep -Fc "PROJECT_ROOT=$tmp/epsilon" "$boot_marker" 2>/dev/null || echo 0)"
  tmux kill-session -t "$boot_sess" >/dev/null 2>&1 || true

  # (j) dev-team.env vorhanden (MUX_SESSION bekannt), aber ohne BOOT_CMD -> weiterhin "Boot
  # nicht möglich", kein Crash. Die neue start_cmd-Konstruktion (liest+quoted envf VOR der
  # boot_cmd-Prüfung) darf diesen bestehenden Fall nicht verändern/brechen.
  mkdir -p "$tmp/zeta/_dev_team/standup"
  ZE="$tmp/zeta/_dev_team/standup"
  echo "z | @Deb | hallo" > "$ZE/_inbox.md"
  zeta_sess="inbox_watch_spec_zeta_$$"
  printf 'export TEAM_LEAD="Deb"\nexport MUX_SESSION="%s"\n' "$zeta_sess" > "$tmp/zeta/_dev_team/dev-team.env"
  python3 - "$tmp/registry.json" "$tmp/zeta" "$ZE" <<'PY'
import json, sys
p, path, standup = sys.argv[1], sys.argv[2], sys.argv[3]
d = json.load(open(p))
d["projects"].append({"uid": "zeta", "name": "zeta", "path": path, "standup": standup, "status": "active"})
json.dump(d, open(p, "w"))
PY
  out="$(BOBNET_MUX=tmux DEV_TEAM_REGISTRY="$tmp/registry.json" INBOX_WATCH_STATE="$tmp/state" INBOX_WATCH_BOOT=1 bash "$BIN" 2>/dev/null)"; rc=$?
  t "(j) fehlendes BOOT_CMD -> exit weiterhin 0" "0" "$rc"
  t "(j) ... unveränderte Meldung, kein Crash" "1" "$(printf '%s\n' "$out" | grep -c 'zeta:.*Boot nicht möglich')"
else
  echo "HINWEIS: tmux nicht verfügbar — Boot-Pfad-Tests (i)/(j) übersprungen"
fi

echo "inbox_watch_spec: $pass passed, $fail failed"
[ "$fail" = 0 ]
