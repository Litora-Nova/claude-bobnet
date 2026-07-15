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
  kill-session) rm -f "$S/${2:?}"; echo "kill-session ${2}" >> "$S/calls.log" ;;
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

echo "── recycle_spec: $pass ✓ / $fail ✗"
[ "$fail" = 0 ]
