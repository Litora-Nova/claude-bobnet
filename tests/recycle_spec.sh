#!/usr/bin/env bash
# tests/recycle_spec.sh — bin/recycle (geordneter Lead-Session-Tausch: Übergabe→Kill→Boot→Verify).
#
# Black-Box wie die Geschwister-Specs: mktemp-Fixtures, NIE echte Registry/Sessions. Der
# Multiplexer wird über einen fake-tmux-Shim im PATH simuliert (BOBNET_MUX=tmux): Sessions =
# State-Files, jeder Aufruf landet in calls.log — so ist der komplette Phasen-Automat inkl.
# Kill/Boot deterministisch prüfbar, ohne dass irgendwo eine echte Session angefasst wird.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN="$HERE/../bin/recycle"
pass=0; fail=0
t(){ local d="$1" exp="$2" got="$3"; if [ "$got" = "$exp" ]; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL: $d — erwartet '$exp', bekam '$got'"; fi; }
ok(){ local d="$1"; shift; if "$@" >/dev/null 2>&1; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL: $d"; fi; }

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
ok "bash -n sauber" bash -n "$BIN"

# ── Fixtures: Registry + 3 Projekte (alpha komplett · beta ohne BOOT_CMD · gamma ohne MUX_SESSION) ─
mkdir -p "$tmp/alpha/_dev_team/standup" "$tmp/beta/_dev_team/standup" "$tmp/gamma/_dev_team/standup" \
         "$tmp/mux" "$tmp/bin"
cat > "$tmp/registry.json" <<JSON
{ "version":1, "projects":[
  {"uid":"alpha","name":"alpha","path":"$tmp/alpha","standup":"$tmp/alpha/_dev_team/standup","status":"active"},
  {"uid":"beta","name":"beta","path":"$tmp/beta","standup":"$tmp/beta/_dev_team/standup","status":"active"},
  {"uid":"gamma","name":"gamma","path":"$tmp/gamma","standup":"$tmp/gamma/_dev_team/standup","status":"active"}
]}
JSON
printf 'export TEAM_LEAD="Zed"\nexport MUX_SESSION="alpha_sess"\nexport BOOT_CMD="echo boot-alpha"\n' > "$tmp/alpha/_dev_team/dev-team.env"
printf 'export TEAM_LEAD="Yui"\nexport MUX_SESSION="beta_sess"\n' > "$tmp/beta/_dev_team/dev-team.env"
printf 'export TEAM_LEAD="Rex"\n' > "$tmp/gamma/_dev_team/dev-team.env"

# fake tmux: Sessions als Dateien unter $FAKE_MUX_DIR, alle Aufrufe → calls.log.
cat > "$tmp/bin/tmux" <<'SH'
#!/usr/bin/env bash
S="${FAKE_MUX_DIR:?}"
cmd="${1:-}"; shift || true
case "$cmd" in
  has-session)  [ -e "$S/${2:?}" ] ;;
  kill-session)
    name="${2:?}"
    # .attached simuliert den Feld-Race: der Kill wurde angefordert, aber ein Client hält die
    # alte Session noch kurz fest. Nach Detach entfernt der Retry sie normal.
    [ -e "$S/$name.attached" ] || rm -f "$S/$name"
    echo "kill-session $name" >> "$S/calls.log" ;;
  list-clients)
    name=""
    while [ $# -gt 0 ]; do
      case "$1" in -t) name="$2"; shift 2 ;; -F) shift 2 ;; *) shift ;; esac
    done
    [ -e "$S/$name.attached" ] && echo "client-1"
    : ;;
  send-keys)    echo "send-keys $*" >> "$S/calls.log" ;;
  list-sessions) ls "$S" 2>/dev/null | grep -v '^calls\.log$' ;;
  new-session)
    name=""; rest=""
    while [ $# -gt 0 ]; do
      case "$1" in
        -d) shift ;;
        -s) name="$2"; shift 2 ;;
        *)  rest="$rest $1"; shift ;;
      esac
    done
    : > "$S/${name:?}"; echo "new-session $name ::$rest" >> "$S/calls.log" ;;
  *) exit 0 ;;
esac
SH
chmod +x "$tmp/bin/tmux"

A="$tmp/alpha/_dev_team/standup"
now(){ date '+%Y-%m-%d %H:%M'; }
run(){ # run <extra-env…> -- <args…>
  local envs=()
  while [ "$1" != "--" ]; do envs+=("$1"); shift; done; shift
  # Overrides ("${envs[@]}") stehen bewusst HINTER den Defaults — bei env gewinnt der letzte Wert.
  env DEV_TEAM_REGISTRY="$tmp/registry.json" BOBNET_MUX=tmux \
      PATH="$tmp/bin:$PATH" FAKE_MUX_DIR="$tmp/mux" \
      RECYCLE_POLL_S=1 RECYCLE_HANDOVER_TIMEOUT_S=10 RECYCLE_BOOT_TIMEOUT_S=10 \
      "${envs[@]}" bash "$BIN" "$@" </dev/null 2>&1
}

# ── Usage / Auflösung ─────────────────────────────────────────────────────────────────────────────
out="$(run X=1 -- --help)"; t "--help → rc 0" "0" "$?"
case "$out" in *Usage*) pass=$((pass+1));; *) fail=$((fail+1)); echo "FAIL: --help ohne Usage-Text";; esac
run X=1 -- >/dev/null; t "keine Args → rc 2" "2" "$?"
run X=1 -- unbekannt --yes >/dev/null; t "unbekannte UID → rc 64" "64" "$?"

# ── Konfig-Gates: NIE killen ohne vollständigen Kontrakt ─────────────────────────────────────────
out="$(run X=1 -- gamma --yes)"; t "MUX_SESSION fehlt → rc 65" "65" "$?"
: > "$tmp/mux/beta_sess"
out="$(run X=1 -- beta --yes)"; t "BOOT_CMD fehlt → rc 65" "65" "$?"
case "$out" in *"NICHT gekillt"*) pass=$((pass+1));; *) fail=$((fail+1)); echo "FAIL: BOOT_CMD-Fehlermeldung nennt Kill-Schutz nicht";; esac
ok "beta_sess wurde dabei NICHT angefasst" test -e "$tmp/mux/beta_sess"

# ── busy/blocked-Gate ────────────────────────────────────────────────────────────────────────────
: > "$tmp/mux/alpha_sess"
echo "$(now) | busy | mitten in Arbeit" > "$A/Zed.log"
run X=1 -- alpha --yes >/dev/null; t "Lead busy (frisch) → rc 3" "3" "$?"
out="$(run X=1 -- alpha --yes --force --dry-run)"; t "--force + --dry-run übersteuert Gate → rc 0" "0" "$?"

# ── non-interaktiv ohne --yes ────────────────────────────────────────────────────────────────────
echo "$(now) | idle | warte" > "$A/Zed.log"
run X=1 -- alpha >/dev/null; t "non-interaktiv ohne --yes → rc 2" "2" "$?"

# ── dry-run: keinerlei Eingriff ──────────────────────────────────────────────────────────────────
: > "$tmp/mux/calls.log"
out="$(run X=1 -- alpha --dry-run)"; t "dry-run (idle) → rc 0" "0" "$?"
case "$out" in *"(dry-run)"*) pass=$((pass+1));; *) fail=$((fail+1)); echo "FAIL: dry-run-Ausgabe fehlt";; esac
t "dry-run: kein kill/new-session/send" "0" "$(grep -c -E 'kill-session|new-session|send-keys' "$tmp/mux/calls.log")"

# ── voller graceful Flow: Übergabe quittiert → Kill → Boot → Verify ──────────────────────────────
: > "$tmp/mux/calls.log"; : > "$tmp/mux/alpha_sess"
echo "$(now) | idle | warte" > "$A/Zed.log"
( sleep 2; echo "$(now) | done | recycle-ready" >> "$A/Zed.log" ) &
( for _ in $(seq 1 30); do
    sleep 0.5
    if grep -q new-session "$tmp/mux/calls.log" 2>/dev/null; then
      sleep 0.5; echo "$(now) | busy | stand-up nach recycle" >> "$A/Zed.log"; break
    fi
  done ) &
out="$(run X=1 -- alpha --yes)"; rc=$?
wait
t "graceful Flow → rc 0" "0" "$rc"
t "Übergabe-Bitte gesendet" "1" "$(grep -c 'send-keys.*RECYCLE' "$tmp/mux/calls.log" | head -n1)"
t "Session gekillt" "1" "$(grep -c 'kill-session alpha_sess' "$tmp/mux/calls.log")"
t "Session frisch gebootet (BOOT_CMD)" "1" "$(grep -c 'new-session alpha_sess.*boot-alpha' "$tmp/mux/calls.log")"
ok "Session-File existiert wieder" test -e "$tmp/mux/alpha_sess"
ok "Boot-Briefing liegt inbox-first" grep -q "Recycle" "$A/_inbox.md"
case "$out" in *"recycle: OK"*) pass=$((pass+1));; *) fail=$((fail+1)); echo "FAIL: OK-Summary fehlt: $out";; esac

# ── Übergabe-Timeout: ABBRUCH ohne Kill (kein Auto---hard) ───────────────────────────────────────
: > "$tmp/mux/calls.log"; : > "$tmp/mux/alpha_sess"
echo "$(now) | idle | warte" > "$A/Zed.log"
out="$(run RECYCLE_HANDOVER_TIMEOUT_S=3 -- alpha --yes)"; t "Übergabe-Timeout → rc 4" "4" "$?"
t "Timeout: NICHT gekillt" "0" "$(grep -c 'kill-session' "$tmp/mux/calls.log")"
ok "Timeout: Session lebt noch" test -e "$tmp/mux/alpha_sess"
case "$out" in *"--hard"*) pass=$((pass+1));; *) fail=$((fail+1)); echo "FAIL: Timeout-Meldung ohne --hard-Hinweis";; esac

# ── --hard: keine Übergabe, Boot ohne Heartbeat → rc 6 (unverifiziert) ───────────────────────────
: > "$tmp/mux/calls.log"; : > "$tmp/mux/alpha_sess"
echo "$(now) | idle | alter Stand" > "$A/Zed.log"
out="$(run RECYCLE_BOOT_TIMEOUT_S=2 -- alpha --yes --hard)"; t "--hard ohne Heartbeat → rc 6" "6" "$?"
t "--hard: keine Übergabe-Bitte" "0" "$(grep -c 'send-keys.*RECYCLE' "$tmp/mux/calls.log")"
t "--hard: gekillt + gebootet" "1" "$(grep -c 'new-session alpha_sess' "$tmp/mux/calls.log")"
case "$out" in *HARD*) pass=$((pass+1));; *) fail=$((fail+1)); echo "FAIL: HARD-Lagebild fehlt";; esac

# ── Session down: Übergabe/Kill entfallen, recycle == Boot ───────────────────────────────────────
: > "$tmp/mux/calls.log"; rm -f "$tmp/mux/alpha_sess"
echo "$(now) | idle | warte" > "$A/Zed.log"
( for _ in $(seq 1 30); do
    sleep 0.5
    if grep -q new-session "$tmp/mux/calls.log" 2>/dev/null; then
      sleep 0.5; echo "$(now) | busy | stand-up nach boot" >> "$A/Zed.log"; break
    fi
  done ) &
out="$(run X=1 -- alpha --yes)"; rc=$?
wait
t "Session down → recycle == Boot, rc 0" "0" "$rc"
t "down: kein kill, kein send" "0" "$(grep -c -E 'kill-session|send-keys' "$tmp/mux/calls.log")"
t "down: gebootet" "1" "$(grep -c 'new-session alpha_sess' "$tmp/mux/calls.log")"

# ── recycle v2 (1): attached Client vor Boot — warten/retry oder klar blockieren ────────────────
: > "$tmp/mux/calls.log"; : > "$tmp/mux/alpha_sess"; : > "$tmp/mux/alpha_sess.attached"
echo "$(now) | idle | alter Stand" > "$A/Zed.log"
( sleep 2; rm -f "$tmp/mux/alpha_sess.attached" ) & detach_pid=$!
( for _ in $(seq 1 30); do
    sleep 0.5
    if grep -q new-session "$tmp/mux/calls.log" 2>/dev/null; then
      echo "$(now) | busy | stand-up nach attached-race" >> "$A/Zed.log"; break
    fi
  done ) & beat_pid=$!
out="$(run RECYCLE_ATTACHED_WAIT_S=5 RECYCLE_ATTACHED_POLL_S=1 -- alpha --yes --hard)"; rc=$?
wait "$detach_pid" "$beat_pid"
t "v2 attached: Client löst sich im Wartefenster → Recycle gelingt" "0" "$rc"
case "$out" in *"Interaktiver Client hängt noch"*) pass=$((pass+1));; *) fail=$((fail+1)); echo "FAIL: v2 attached: Warnung fehlt";; esac
t "v2 attached: alte Session nach Detach erneut gekillt" "2" "$(grep -c 'kill-session alpha_sess' "$tmp/mux/calls.log")"
t "v2 attached: frischer Boot genau einmal" "1" "$(grep -c 'new-session alpha_sess' "$tmp/mux/calls.log")"

: > "$tmp/mux/calls.log"; : > "$tmp/mux/alpha_sess"; : > "$tmp/mux/alpha_sess.attached"
echo "$(now) | idle | alter Stand" > "$A/Zed.log"
out="$(run RECYCLE_ATTACHED_WAIT_S=2 RECYCLE_ATTACHED_POLL_S=1 -- alpha --yes --hard)"; rc=$?
t "v2 attached: persistenter Client blockiert mit rc 5" "5" "$rc"
case "$out" in *"frischer Boot blockiert"*) pass=$((pass+1));; *) fail=$((fail+1)); echo "FAIL: v2 attached: Blocker-Meldung fehlt";; esac
t "v2 attached: bei Blocker KEIN neuer Boot" "0" "$(grep -c 'new-session' "$tmp/mux/calls.log")"
rm -f "$tmp/mux/alpha_sess.attached" "$tmp/mux/alpha_sess"

# ── recycle v2 (2): zellij-Lifecycle — EXITED != live, kill + delete, frischer Spawn ───────────
cat > "$tmp/bin/zellij" <<'SH'
#!/usr/bin/env bash
S="${FAKE_MUX_DIR:?}"
cmd="${1:-}"; shift || true
case "$cmd" in
  list-sessions)
    for f in "$S"/zj-*.live; do
      [ -e "$f" ] || continue; name="${f##*/zj-}"; name="${name%.live}"
      if [ -e "$S/zj-$name.attached" ]; then echo "$name [Created now] (current)"
      else echo "$name [Created now]"; fi
    done
    for f in "$S"/zj-*.exited; do
      [ -e "$f" ] || continue; name="${f##*/zj-}"; name="${name%.exited}"
      echo "$name [Created ago] (EXITED - attach to resurrect)"
    done ;;
  --session)
    name="${1:?}"; shift
    [ "${1:-}" = action ] && [ "${2:-}" = list-clients ] || exit 1
    [ -e "$S/zj-$name.live" ] || exit 1
    echo "CLIENT_ID ZELLIJ_PANE_ID RUNNING_COMMAND"
    [ -e "$S/zj-$name.attached" ] && echo "1 terminal_1 claude"
    exit 0 ;;
  kill-session)
    name="${1:?}"; echo "zellij-kill $name" >> "$S/calls.log"
    if [ -e "$S/zj-$name.live" ]; then rm -f "$S/zj-$name.live"; : > "$S/zj-$name.exited"; fi ;;
  delete-session)
    name="${1:?}"; echo "zellij-delete $name" >> "$S/calls.log"
    rm -f "$S/zj-$name.exited" ;;
  attach)
    name="${2:?}"; echo "zellij-attach $name" >> "$S/calls.log"
    [ -e "$S/zj-$name.exited" ] && echo "resurrected $name" >> "$S/calls.log"
    : > "$S/zj-$name.live" ;;
  *) exit 0 ;;
esac
SH
chmod +x "$tmp/bin/zellij"
MUX_LIB="$HERE/../scripts/lib/mux.sh"
mux_zj(){ env BOBNET_MUX=zellij PATH="$tmp/bin:$PATH" FAKE_MUX_DIR="$tmp/mux" \
  bash -c '. "$1"; shift; "$@"' _ "$MUX_LIB" "$@"; }

: > "$tmp/mux/calls.log"; : > "$tmp/mux/zj-shell.exited"
mux_zj mux_has shell >/dev/null 2>&1; t "v2 zellij: EXITED-Hülle zählt NICHT als live" "1" "$?"
t "v2 zellij: mux_list blendet EXITED-Hülle aus" "0" "$(mux_zj mux_list | grep -c '^shell$')"
mux_zj mux_spawn shell >/dev/null 2>&1; t "v2 zellij: frischer Spawn nach EXITED-Hülle gelingt" "0" "$?"
t "v2 zellij: EXITED-State vor Attach gelöscht (keine Resurrection)" "0" "$(grep -c 'resurrected shell' "$tmp/mux/calls.log")"
ok "v2 zellij: frische Live-Session existiert" test -e "$tmp/mux/zj-shell.live"

: > "$tmp/mux/zj-shell.attached"
mux_zj mux_attached shell >/dev/null 2>&1; t "v2 zellij: attached/current Client erkannt" "0" "$?"
rm -f "$tmp/mux/zj-shell.attached"
mux_zj mux_attached shell >/dev/null 2>&1; t "v2 zellij: clientlose Live-Session ist detached" "1" "$?"
: > "$tmp/mux/calls.log"
mux_zj mux_kill shell >/dev/null 2>&1; t "v2 zellij: mux_kill beendet Live-Session + Hülle" "0" "$?"
t "v2 zellij: kill-session und delete-session liefen BEIDE" "2" "$(grep -cE 'zellij-(kill|delete) shell' "$tmp/mux/calls.log")"
ok "v2 zellij: weder live noch EXITED bleibt" bash -c "test ! -e '$tmp/mux/zj-shell.live' && test ! -e '$tmp/mux/zj-shell.exited'"

# ── recycle v2 (3): optionaler Prozess-Verify = Heartbeat UND Agent mit Projekt-CWD ──────────
procroot="$tmp/proc"; mkdir -p "$procroot"
: > "$tmp/mux/calls.log"; : > "$tmp/mux/alpha_sess"
echo "$(now) | idle | alter Stand" > "$A/Zed.log"
( for _ in $(seq 1 30); do
    sleep 0.5
    if grep -q new-session "$tmp/mux/calls.log" 2>/dev/null; then
      mkdir -p "$procroot/9001"; ln -s "$tmp/alpha" "$procroot/9001/cwd"
      printf 'claude\n' > "$procroot/9001/comm"; printf '/usr/bin/claude\0' > "$procroot/9001/cmdline"
      echo "$(now) | busy | stand-up mit Prozess" >> "$A/Zed.log"; break
    fi
  done ) & proc_pid=$!
out="$(run RECYCLE_VERIFY_PROCESS=1 RECYCLE_PROC_ROOT="$procroot" RECYCLE_BOOT_TIMEOUT_S=5 -- alpha --yes --hard)"; rc=$?
wait "$proc_pid"
t "v2 process: Heartbeat + Agentprozess mit Projekt-CWD → rc 0" "0" "$rc"
case "$out" in *"Agent-Prozess läuft mit Projekt-CWD"*) pass=$((pass+1));; *) fail=$((fail+1)); echo "FAIL: v2 process: Erfolgsnachweis fehlt";; esac
rm -rf "$procroot/9001"

: > "$tmp/mux/calls.log"; : > "$tmp/mux/alpha_sess"
echo "$(now) | idle | alter Stand" > "$A/Zed.log"
( for _ in $(seq 1 30); do
    sleep 0.5
    if grep -q new-session "$tmp/mux/calls.log" 2>/dev/null; then
      echo "$(now) | busy | Heartbeat ohne Agentprozess" >> "$A/Zed.log"; break
    fi
  done ) & beat_only_pid=$!
out="$(run RECYCLE_VERIFY_PROCESS=1 RECYCLE_PROC_ROOT="$procroot" RECYCLE_BOOT_TIMEOUT_S=2 -- alpha --yes --hard)"; rc=$?
wait "$beat_only_pid"
t "v2 process: Heartbeat allein reicht bei Opt-in NICHT → rc 6" "6" "$rc"
case "$out" in *"Kein passender Agent-Prozess"*) pass=$((pass+1));; *) fail=$((fail+1)); echo "FAIL: v2 process: fehlender-Prozess-Meldung fehlt";; esac

echo "── recycle_spec: $pass ✓ / $fail ✗"
[ "$fail" = 0 ]
