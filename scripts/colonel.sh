#!/usr/bin/env bash
# colonel.sh — Colonel, der Bobiverse-SINGLETON-Disziplin-Wächter (Phase F).
#
# Archetyp: process-auditor ("Mario → Colonel" — Disziplin > Kreativität). EIN Colonel pro
# Bobiverse (maschinen-/installations-weit, NICHT pro Projekt — das ist GUPPIs Revier). Er prüft
# wiederkehrend, mechanisch, urteils-arm, ob der Laden diszipliniert läuft, und meldet ✓/⚠/✗.
#
# ── Was Colonel prüft (jeder Check = eine Zeile ✓/⚠/✗ + fließt in den Exit-Code) ────────────────
#   1  BobNet/Dashboard läuft?   :3030 erreichbar (HTTP) ODER ein bobnet-Prozess da.
#                                ⊘ wenn BobNet bewusst nicht genutzt wird (bobiverse.json bobnet=null
#                                   UND kein Launcher) → BobNet ist optional (PLAN §5), kein ✗.
#   2  Prozesse                  verwaiste/zombie Agent-/tmux-Prozesse? (hängende Bobs, alte
#                                Dev-Server, defunct). Reine Beobachtung, kein Kill.
#   3  Engine in sync?           git ahead/behind/dirty gegen origin (Engine-Repo; +BobNet-Repo
#                                falls registriert). Drift = ⚠ (nicht ✗ — Sync ist erlaubt-pending).
#   4  Lead orchestriert         ⚠️ FUZZY-HEURISTIK (Platzhalter, siehe Block unten). Erkennt grob,
#      statt Aktionismus         ob der Team-Lead selbst Code schaufelt während Worker idle sind.
#
# ── ⚠️ HEURISTIK „Lead orchestriert statt Aktionismus" (VORSCHLAG an Bob — bitte schärfen) ───────
#   PROBLEM: „Aktionismus" ist sozial/fuzzy; ein Script kann Intent nicht messen. Vorgeschlagene,
#   MECHANISCH prüfbare Proxys (Schwellen frei justierbar via Env), aktuell als PLATZHALTER
#   implementiert (zählt nur + meldet, blockt nicht hart):
#
#     (a) LEAD_COMMIT_RATIO — Anteil der Commits im Fenster (Default 24h), die vom Team-Lead
#         (TEAM_LEAD / git-author) stammen. > Schwelle (Default 0.70) ⇒ ⚠ „Lead committet das
#         meiste selbst" — Indiz, dass delegiert werden sollte. (git log --author, kein Intent.)
#     (b) LEAD_BUSY_WHILE_WORKERS_IDLE — Lead-Heartbeat 'busy' im Fenster, während ≥N Worker
#         (Default 2) durchgehend 'idle' → ⚠ „Lead arbeitet, Team steht". (standup/*.log auswertbar.)
#     (c) BIG_TASK_NO_DELEGATION — großer Lead-Commit (Default ≥ 400 LOC netto) ohne dass im selben
#         Fenster ein Worker-Branch/-Heartbeat zum selben Thema existiert → ⚠ „große Aufgabe ohne
#         Hand-off". (Am schwächsten — Thema-Matching ist heuristisch; vorerst NICHT scharf.)
#
#   Implementiert ist HEUTE nur (a) als realer Zähler + ein klar markierter Platzhalter-Rahmen für
#   (b)/(c). Alle drei sind als Design-Liste an Bob geflaggt (siehe Heartbeat/Final-Report). Bis Bob
#   eine Schwelle freigibt, ist dieser Check IMMER nur ⚠/✓, NIE ✗ (Exit-neutral konfigurierbar via
#   COLONEL_AKTIONISMUS_FATAL=0|1, Default 0 = nur warnen).
#
# ── Schedule-Mechanik (VORSCHLAG an Bob) ─────────────────────────────────────────────────────────
#   Colonel ist „permanent" gemeint. Optionen (Design-Liste an Bob, NICHT hier hart verdrahtet):
#     • cron alle 30–60 min (analog cron/cron-health.sh) — einfachste, robusteste Variante. ✅ Empf.
#     • ODER GUPPI-getriggert (guppi.sh ruft colonel.sh als Sub-Check) — koppelt aber Singleton an
#       Projekt-Service, unschön. Lieber eigener cron-Eintrag `cron/cron-colonel.sh` (Phase-F-Folge).
#   Dieses Script ist NUR die Mechanik (ein Lauf = ein Report). Das WANN gehört in den Scheduler.
#
# ── Env ──────────────────────────────────────────────────────────────────────────────────────────
#   ENGINE_ROOT          Engine-Repo-Root (Default: 2 Ebenen über diesem Script).
#   BOBIVERSE_CONFIG     ~/.claude/bobiverse.json (engine/bobnet/version). Default: $HOME/.claude/bobiverse.json
#   BOBNET_URL           Dashboard-Endpoint (Default http://localhost:3030).
#   COLONEL_GIT_WINDOW   Zeitfenster für Commit-Heuristik (Default '24 hours ago').
#   COLONEL_LEAD_RATIO   Schwelle (a) Lead-Commit-Anteil (Default 0.70).
#   TEAM_LEAD            Name des Team-Leads für Heuristik (Default Bob).
#   STANDUP_DIR          Heartbeat-Logs (für Heuristik b; optional).
#   COLONEL_AKTIONISMUS_FATAL  1 = Heuristik darf ✗ setzen (Exit), Default 0 = nur ⚠.
#   DEV_TEAM_TZ          Zeitzone (Default Europe/Berlin).
#   --self-test          mktemp-Fixtures, KEIN echter Prozess-/Netz-Effekt; prüft die Check-Logik.
#
# Exit:  0 = alle Checks ✓/⊘   |   1 = mindestens ein ✗ (echter Disziplin-Bruch).
#        ⚠ allein setzt Exit NICHT auf 1 (Warnung ≠ Bruch), außer COLONEL_AKTIONISMUS_FATAL=1 greift.
set -uo pipefail

BIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENGINE_ROOT="${ENGINE_ROOT:-$(cd "$BIN_DIR/.." && pwd)}"
# shellcheck source=lib/mux.sh
. "$BIN_DIR/lib/mux.sh"   # Multiplexer-Adapter (tmux|zellij) — nie direkt tmux/zellij rufen
BOBIVERSE_CONFIG="${BOBIVERSE_CONFIG:-$HOME/.claude/bobiverse.json}"
BOBNET_URL="${BOBNET_URL:-http://localhost:3030}"
GIT_WINDOW="${COLONEL_GIT_WINDOW:-24 hours ago}"
LEAD_RATIO_MAX="${COLONEL_LEAD_RATIO:-0.70}"
LEAD_NAME="${TEAM_LEAD:-Bob}"
AKTIONISMUS_FATAL="${COLONEL_AKTIONISMUS_FATAL:-0}"
TZc="${DEV_TEAM_TZ:-Europe/Berlin}"

FAIL=0       # ✗-Zähler → Exit
WARN=0       # ⚠-Zähler (kosmetisch, außer Aktionismus-fatal)

pass() { printf '  ✓ %s\n' "$*"; }
warn() { printf '  ⚠ %s\n' "$*"; WARN=$((WARN+1)); }
fail() { printf '  ✗ %s\n' "$*"; FAIL=$((FAIL+1)); }
skip() { printf '  ⊘ %s\n' "$*"; }

# json_field <datei> <feld> — liest ein Top-Level-Feld aus einer JSON-Datei (jq-frei, wie der Rest).
json_field() {
  CFG="$1" KEY="$2" python3 - <<'PY' 2>/dev/null
import json, os, sys
try:
    with open(os.environ["CFG"]) as fh:
        data = json.load(fh)
except Exception:
    sys.exit(0)
v = data.get(os.environ["KEY"]) if isinstance(data, dict) else None
if v is None:
    sys.exit(0)
sys.stdout.write(str(v))
PY
}

# ── Check 1: BobNet/Dashboard ────────────────────────────────────────────────────────────────────
check_bobnet() {
  echo "[1/4] BobNet / Dashboard"
  local bobnet_cfg launcher
  bobnet_cfg="$(json_field "$BOBIVERSE_CONFIG" bobnet)"
  launcher="${BOBNET_LAUNCHER:-$(cd "$ENGINE_ROOT/.." && pwd)/claude-team-dashboard/start}"

  # HTTP-Probe (wenn curl da) — schnell, harmlos, max-time kurz.
  local sc=""
  if command -v curl >/dev/null 2>&1; then
    sc="$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 "$BOBNET_URL" 2>/dev/null)"
  fi
  # Prozess-Probe (Fallback / Ergänzung): Multiplexer-Session 'bobnet' ODER ein Nuxt/Node am Dashboard.
  local proc=""
  if pgrep -fa "claude-team-dashboard|bobnet" >/dev/null 2>&1; then proc="yes"; fi

  if [ "$sc" = "200" ]; then
    pass "BobNet erreichbar ($BOBNET_URL → 200)"
  elif [ -n "$proc" ]; then
    warn "BobNet-Prozess läuft, aber $BOBNET_URL nicht 200 (sc=${sc:-n/a}) — bootend/wedged?"
  elif [ -z "$bobnet_cfg" ] || [ "$bobnet_cfg" = "None" ] || [ "$bobnet_cfg" = "null" ]; then
    if [ -f "$launcher" ]; then
      warn "BobNet konfiguriert nutzbar (Launcher da), aber nicht gestartet ($BOBNET_URL)"
    else
      skip "Kein BobNet (bobiverse.json bobnet=null, kein Launcher) — BobNet ist optional (PLAN §5)"
    fi
  else
    fail "BobNet erwartet (bobnet=$bobnet_cfg) aber nicht erreichbar/kein Prozess ($BOBNET_URL)"
  fi
}

# ── Check 2: Prozesse (verwaist/zombie) ────────────────────────────────────────────────────────────
check_processes() {
  echo "[2/4] Prozesse (verwaist / zombie)"
  # Zombies/defunct — Eltern-Reap-Problem, klares Symptom hängender Agents.
  local zombies=0
  if command -v ps >/dev/null 2>&1; then
    zombies="$(ps -eo stat= 2>/dev/null | grep -c '^Z' || true)"
  fi
  [ -z "$zombies" ] && zombies=0
  if [ "$zombies" -gt 0 ]; then
    warn "$zombies Zombie/defunct-Prozess(e) — Eltern reapt nicht (hängender Agent?)"
  else
    pass "keine Zombie-Prozesse"
  fi

  # Multiplexer-Sessions: Inventar (kein Kill, nur Beobachtung). Erwartete: bob/scut/bobnet/<projekt>_bob.
  local mux sessions n
  mux="$(mux_backend 2>/dev/null)"
  if [ -n "$mux" ]; then
    sessions="$(mux_list 2>/dev/null)"
    n="$(printf '%s' "$sessions" | grep -c . || true)"
    if [ "${n:-0}" -gt 0 ]; then
      pass "$mux: $n Session(s) aktiv — $(printf '%s' "$sessions" | paste -sd' ' -)"
    else
      skip "kein $mux-Session aktiv (lokaler Lauf ohne Daemons?)"
    fi
  else
    skip "kein Multiplexer (tmux/zellij) gefunden"
  fi
}

# ── Check 3: Engine (+ ggf. BobNet-Repo) in sync gegen origin ──────────────────────────────────────
# git_sync_state <repo-dir> — gibt "clean" | "dirty" | "ahead N" | "behind N" | "diverged" | "no-upstream" | "no-repo".
git_sync_state() {
  local d="$1"
  [ -d "$d/.git" ] || { printf 'no-repo'; return; }
  git -C "$d" rev-parse --is-inside-work-tree >/dev/null 2>&1 || { printf 'no-repo'; return; }
  # Dirty-Working-Tree?
  if [ -n "$(git -C "$d" status --porcelain 2>/dev/null)" ]; then printf 'dirty'; return; fi
  local up; up="$(git -C "$d" rev-parse --abbrev-ref --symbolic-full-name '@{upstream}' 2>/dev/null)"
  [ -z "$up" ] && { printf 'no-upstream'; return; }
  local counts ahead behind
  counts="$(git -C "$d" rev-list --left-right --count "@{upstream}...HEAD" 2>/dev/null)"
  behind="${counts%%	*}"; ahead="${counts##*	}"
  behind="${behind:-0}"; ahead="${ahead:-0}"
  if [ "$ahead" -gt 0 ] && [ "$behind" -gt 0 ]; then printf 'diverged %s/%s' "$ahead" "$behind"
  elif [ "$ahead" -gt 0 ]; then printf 'ahead %s' "$ahead"
  elif [ "$behind" -gt 0 ]; then printf 'behind %s' "$behind"
  else printf 'clean'; fi
}

report_sync() {
  local label="$1" state="$2"
  case "$state" in
    clean)        pass "$label sync: clean (== origin)";;
    no-repo)      skip "$label: kein git-Repo — übersprungen";;
    no-upstream)  warn "$label: kein Upstream gesetzt (kein origin-Tracking)";;
    dirty)        warn "$label: dirty Working-Tree (uncommitted) — Feierabend-Disziplin (CLAUDE.md)";;
    ahead*)       warn "$label: ${state#ahead } Commit(s) ahead — un-gepusht (push gehört zum Sync)";;
    behind*)      warn "$label: ${state#behind } Commit(s) behind — pull fehlt";;
    diverged*)    warn "$label: diverged (${state#diverged }) — rebase/merge nötig";;
    *)            warn "$label: unklarer Sync-Status ($state)";;
  esac
}

check_sync() {
  echo "[3/4] Sync gegen origin"
  report_sync "Engine" "$(git_sync_state "$ENGINE_ROOT")"
  # BobNet-Repo, falls die Config einen Pfad nennt (bobnet kann Pfad/URL/Objekt sein → tolerant).
  local bobnet_cfg; bobnet_cfg="$(json_field "$BOBIVERSE_CONFIG" bobnet)"
  if [ -n "$bobnet_cfg" ] && [ "$bobnet_cfg" != "None" ] && [ "$bobnet_cfg" != "null" ] && [ -d "$bobnet_cfg/.git" ]; then
    report_sync "BobNet" "$(git_sync_state "$bobnet_cfg")"
  fi
}

# ── Check 4: Lead orchestriert statt Aktionismus (FUZZY — Platzhalter, siehe Header) ────────────────
check_aktionismus() {
  echo "[4/4] Lead orchestriert statt Aktionismus (⚠ Heuristik — Platzhalter)"
  # (a) Lead-Commit-Anteil im Fenster. Real implementiert, aber nur ⚠ (außer FATAL=1).
  if [ -d "$ENGINE_ROOT/.git" ]; then
    local total lead ratio_msg
    total="$(git -C "$ENGINE_ROOT" log --since="$GIT_WINDOW" --all --pretty='%an' 2>/dev/null | wc -l | tr -d ' ')"
    lead="$(git -C "$ENGINE_ROOT" log --since="$GIT_WINDOW" --all --pretty='%an' 2>/dev/null | grep -cF "$LEAD_NAME" || true)"
    total="${total:-0}"; lead="${lead:-0}"
    if [ "$total" -eq 0 ]; then
      skip "(a) keine Commits im Fenster ($GIT_WINDOW) — nichts zu beurteilen"
    else
      # Bruch-Vergleich ohne bc: lead/total > LEAD_RATIO_MAX  ⇔  lead*100 > ratio%*total.
      local pct; pct="$(awk -v l="$lead" -v t="$total" 'BEGIN{printf "%.2f", (t>0)?l/t:0}')"
      local over; over="$(awk -v r="$pct" -v m="$LEAD_RATIO_MAX" 'BEGIN{print (r>m)?1:0}')"
      if [ "$over" = "1" ]; then
        ratio_msg="(a) Lead-Commit-Anteil $pct > $LEAD_RATIO_MAX ($lead/$total) — delegieren statt selbst schaufeln?"
        if [ "$AKTIONISMUS_FATAL" = "1" ]; then fail "$ratio_msg"; else warn "$ratio_msg"; fi
      else
        pass "(a) Lead-Commit-Anteil $pct ≤ $LEAD_RATIO_MAX ($lead/$total) — Balance ok"
      fi
    fi
  else
    skip "(a) kein git-Repo für Commit-Anteil"
  fi
  # (b)/(c): PLATZHALTER — bewusst nicht scharf (siehe Header-Heuristik-Block + Design-Liste an Bob).
  skip "(b) Lead-busy-while-Workers-idle — PLATZHALTER (Heuristik an Bob geflaggt)"
  skip "(c) große-Aufgabe-ohne-Delegation — PLATZHALTER (Thema-Matching unsicher, an Bob geflaggt)"
}

run_all() {
  local ts; ts="$(TZ="$TZc" date '+%Y-%m-%d %H:%M' 2>/dev/null || date '+%Y-%m-%d %H:%M')"
  echo "=== Colonel — Disziplin-Audit $ts (engine: $ENGINE_ROOT) ==="
  check_bobnet
  check_processes
  check_sync
  check_aktionismus
  echo "--- Colonel: $FAIL ✗ / $WARN ⚠ ---"
  [ "$FAIL" -eq 0 ] && return 0 || return 1
}

# ── Self-Test: mktemp-Fixtures, KEIN echter Prozess-/Netz-Effekt ───────────────────────────────────
self_test() {
  local tmp; tmp="$(mktemp -d "${TMPDIR:-/tmp}/colonel-test.XXXXXX")"
  trap "rm -rf '$tmp'" EXIT
  local fail=0
  check() { if eval "$2"; then printf '  ✓ %s\n' "$3"; else printf '  ✗ %s\n' "$3"; fail=1; fi; }

  # Fixture-Repo 1: clean (committed, dummy-upstream auf sich selbst).
  local r1="$tmp/engine"; mkdir -p "$r1"
  ( cd "$r1" && git init -q && git config user.email t@e && git config user.name T \
      && echo a > a && git add a && git commit -qm init ) >/dev/null 2>&1
  # Self-upstream simulieren: ein bare-Origin + push, damit @{upstream} existiert + clean ist.
  local origin="$tmp/origin.git"; git init -q --bare "$origin" >/dev/null 2>&1
  ( cd "$r1" && git remote add origin "$origin" && git push -q -u origin HEAD:master ) >/dev/null 2>&1

  local st_clean; st_clean="$(git_sync_state "$r1")"
  check x "[ \"$st_clean\" = clean ]" "git_sync_state: clean nach push (war '$st_clean')"

  # Fixture: dirty (uncommitted Änderung).
  echo b >> "$r1/a"
  local st_dirty; st_dirty="$(git_sync_state "$r1")"
  check x "[ \"$st_dirty\" = dirty ]" "git_sync_state: dirty bei uncommitted (war '$st_dirty')"
  ( cd "$r1" && git checkout -q -- a ) >/dev/null 2>&1

  # Fixture: ahead (lokaler Commit ohne push).
  ( cd "$r1" && echo c > c && git add c && git commit -qm c ) >/dev/null 2>&1
  local st_ahead; st_ahead="$(git_sync_state "$r1")"
  check x "[ \"${st_ahead%% *}\" = ahead ]" "git_sync_state: ahead bei un-gepushtem Commit (war '$st_ahead')"

  # Fixture: kein Repo.
  mkdir -p "$tmp/norepo"
  local st_no; st_no="$(git_sync_state "$tmp/norepo")"
  check x "[ \"$st_no\" = no-repo ]" "git_sync_state: no-repo bei Nicht-Git-Ordner (war '$st_no')"

  # json_field: bobnet=null lesbar + leeres bobnet → leer.
  printf '%s\n' '{"engine":"/x","bobnet":null,"version":1}' > "$tmp/bobiverse.json"
  local jf_eng jf_bn
  jf_eng="$(json_field "$tmp/bobiverse.json" engine)"
  jf_bn="$(json_field "$tmp/bobiverse.json" bobnet)"
  check x "[ \"$jf_eng\" = /x ]" "json_field: liest 'engine' (war '$jf_eng')"
  check x "[ -z \"$jf_bn\" ]" "json_field: bobnet=null → leer (war '$jf_bn')"

  # report_sync: clean → ✓ (kein FAIL/WARN), dirty/ahead/behind → ⚠.
  FAIL=0 WARN=0; report_sync "X" clean >/dev/null
  check x "[ \"$FAIL\" = 0 ] && [ \"$WARN\" = 0 ]" "report_sync clean: kein ✗/⚠"
  FAIL=0 WARN=0; report_sync "X" dirty >/dev/null
  check x "[ \"$FAIL\" = 0 ] && [ \"$WARN\" = 1 ]" "report_sync dirty: 1 ⚠, kein ✗"
  FAIL=0 WARN=0; report_sync "X" "ahead 3" >/dev/null
  check x "[ \"$WARN\" = 1 ]" "report_sync ahead: ⚠"

  # check_bobnet: bobnet=null + kein Launcher → ⊘ (kein FAIL). BOBNET_URL ins Leere, kein Prozess.
  FAIL=0 WARN=0
  BOBIVERSE_CONFIG="$tmp/bobiverse.json" BOBNET_URL="http://127.0.0.1:1" \
    ENGINE_ROOT="$tmp/nonexistent-engine" BOBNET_LAUNCHER="$tmp/no-launcher" \
    check_bobnet >/dev/null 2>&1
  check x "[ \"$FAIL\" = 0 ]" "check_bobnet: bobnet=null + kein Launcher → kein ✗ (BobNet optional)"

  # check_aktionismus: leeres Fenster (kein Commit) → kein FAIL.
  FAIL=0 WARN=0
  COLONEL_GIT_WINDOW="1 second ago" ENGINE_ROOT="$tmp/norepo" check_aktionismus >/dev/null 2>&1
  check x "[ \"$FAIL\" = 0 ]" "check_aktionismus: kein git-Repo → kein ✗ (skip)"

  if [ "$fail" = 0 ]; then echo "colonel self-test: GRÜN"; return 0
  else echo "colonel self-test: ROT"; return 1; fi
}

case "${1:-}" in
  --self-test|self-test) self_test; exit $? ;;
  ""|--run|run)          run_all; exit $? ;;
  -h|--help)             sed -n '2,60p' "${BASH_SOURCE[0]}"; exit 0 ;;
  *) echo "Usage: colonel.sh [--run]   |   colonel.sh --self-test   |   colonel.sh --help" >&2; exit 64 ;;
esac
