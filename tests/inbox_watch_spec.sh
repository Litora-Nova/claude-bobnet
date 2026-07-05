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
  {"uid":"leer","name":"leer","path":"$tmp/leer","standup":"$tmp/leer","status":"active"}
]}
JSON
printf 'export TEAM_LEAD="Zed"\nexport MUX_SESSION="alpha_sess"\n' > "$tmp/alpha/_dev_team/dev-team.env"
printf 'export TEAM_LEAD="Yui"\n' > "$tmp/beta/_dev_team/dev-team.env"

A="$tmp/alpha/_dev_team/standup"; B="$tmp/beta/_dev_team/standup"
echo "x | @Zed | hallo" > "$A/_inbox.md"
echo "y | @Yui | hallo" > "$B/_inbox.md"
now(){ date '+%Y-%m-%d %H:%M'; }
run(){ DEV_TEAM_REGISTRY="$tmp/registry.json" INBOX_WATCH_STATE="$tmp/state" INBOX_WATCH_DRYRUN=1 bash "$BIN" 2>/dev/null; }

# Lauf 1: alpha-Lead idle → NUDGE · beta ohne MUX_SESSION → report-only · leer ohne Inbox → skip
echo "$(now) | idle | warte" > "$A/Zed.log"
echo "$(now) | idle | warte" > "$B/Yui.log"
out="$(run)"
t "neu + idle → NUDGE" "1" "$(printf '%s\n' "$out" | grep -c 'alpha: NUDGE → alpha_sess')"
t "ohne MUX_SESSION → report-only" "1" "$(printf '%s\n' "$out" | grep -c 'beta: NEU.*report-only')"
t "ohne _inbox.md → skip" "1" "$(printf '%s\n' "$out" | grep -c 'leer: keine _inbox.md')"
t "exit 0" "0" "$(run >/dev/null; echo $?)"

# Lauf 2: nichts Neues → beide ok (State wurde bei Nudge + report-only fortgeschrieben)
out="$(run)"
t "unverändert → ok (alpha)" "1" "$(printf '%s\n' "$out" | grep -c 'alpha: ok')"
t "unverändert → ok (beta)" "1" "$(printf '%s\n' "$out" | grep -c 'beta: ok')"

# busy (frisch) → skip-busy, State bleibt offen → Wiederholungslauf meldet weiter NEU
echo "neuer eintrag" >> "$A/_inbox.md"
echo "$(now) | busy | arbeite" > "$A/Zed.log"
out="$(run)"
t "neu + busy → skip-busy" "1" "$(printf '%s\n' "$out" | grep -c 'alpha: NEU.*skip-busy')"
out="$(run)"
t "busy-Skip hält State offen (re-check)" "1" "$(printf '%s\n' "$out" | grep -c 'alpha: NEU.*skip-busy')"

# Lead wird done → jetzt NUDGE
echo "$(now) | done | fertig" > "$A/Zed.log"
out="$(run)"
t "done → NUDGE" "1" "$(printf '%s\n' "$out" | grep -c 'alpha: NUDGE')"

# stale-busy: alter busy-Heartbeat zählt als idle
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

# _inbox/-Dateidrop zählt als Neues
mkdir -p "$B/_inbox"; echo bild > "$B/_inbox/foto.txt"
echo "$(now) | idle | warte" > "$B/Yui.log"
out="$(run)"
t "_inbox/-Drop → NEU (beta report-only)" "1" "$(printf '%s\n' "$out" | grep -c 'beta: NEU.*report-only')"

# Review-Queue-Eintrag zählt als Neues (ungerichtete Router-Mails dürfen nicht liegenbleiben)
echo "x | UNGERICHTET (via email, von kunde) | anfrage" >> "$B/_review-queue.md"
out="$(run)"
t "_review-queue.md → NEU (beta report-only)" "1" "$(printf '%s\n' "$out" | grep -c 'beta: NEU.*report-only')"

echo "inbox_watch_spec: $pass passed, $fail failed"
[ "$fail" = 0 ]
