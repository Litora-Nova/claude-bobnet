#!/usr/bin/env bash
# guppi.sh — GUPPI, der pro-Projekt-Bobiverse Helfer-Service (Phase F).
#
# Archetyp: guppi (category=service, ring=shared, model=haiku, tags=[ops]). Urteils-FREIER,
# mechanischer Routine-Executor EINES Projekt-Bobiverse (vs. Colonel = ein Singleton fürs ganze
# Bobiverse). GUPPI rät NIE — bei Drift eskaliert er an den Team-Lead (ops-Regel).
#
# ── Was GUPPI tut (PLAN §10) ───────────────────────────────────────────────────────────────────
#   1  Prozess-/Schedule-Watch   welche Bobs/Daemons/cron laufen für DIESES Projekt? (tmux-Sessions,
#                                cron-Einträge der Engine-Scripts). Reine Beobachtung, kein Kill.
#   2  BobNet-Register-Check      existiert (inzwischen) ein BobNet? (bobiverse.json bobnet-Feld /
#                                Dashboard erreichbar). Falls ja UND dieses Projekt noch nicht in der
#                                zentralen Registry → SELF-REGISTER. Idempotent. Nutzt NICHT-dupliziert
#                                die onboard-Baustein-6-Logik: ruft `bin/onboard "$PROJECT_ROOT"` (das
#                                IST der idempotente Registry-Upsert + non-destruktiv re-runbar).
#   3  SCUT-Input-Routing         leitet eingehende normalisierte Channel-Events an scut-router.sh —
#                                knüpft an den BESTEHENDEN Router an (pipe in scut-router.sh), baut
#                                NICHTS neu. Quelle = stdin ODER eine Queue-Datei (--route <file>).
#
# ── Env ──────────────────────────────────────────────────────────────────────────────────────────
#   ENGINE_ROOT        Engine-Repo-Root (Default: 2 Ebenen über diesem Script).
#   PROJECT_ROOT       Repo-Root dieses Projekt-Bobiverse (Default: aus dev-team.env / CWD).
#   PROJECT_UID        UID des Projekts (für Registry-Match). Default: aus dev-team.env.
#   BOBIVERSE_CONFIG   ~/.claude/bobiverse.json. Default: $HOME/.claude/bobiverse.json
#   BOBNET_URL         Dashboard-Endpoint (Default http://localhost:3030).
#   DEV_TEAM_REGISTRY  zentrale projects.registry.json (Default: <toolhub>/projects.registry.json).
#   STANDUP_DIR        Heartbeat-/Inbox-Ordner des Projekts.
#   GUPPI_REGISTER     1 = darf self-register (onboard aufrufen); 0 = nur prüfen+melden. Default 1.
#   DEV_TEAM_TZ        Zeitzone (Default Europe/Berlin).
#
# ── Subcommands ────────────────────────────────────────────────────────────────────────────────
#   guppi.sh [watch]          alle drei Checks als Report (Default).
#   guppi.sh --route <file>   die Zeilen aus <file> (normalisierte Events) durch scut-router.sh jagen.
#   <channel.sh> | guppi.sh --route    Events von stdin an scut-router.sh durchreichen.
#   guppi.sh --self-test      mktemp-Fixtures, kein echter Effekt.
#
# Exit:  0 = ok   |   1 = ein Check meldete ein echtes Problem (Eskalations-würdig).
set -uo pipefail

BIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENGINE_ROOT="${ENGINE_ROOT:-$(cd "$BIN_DIR/.." && pwd)}"
# shellcheck source=lib/mux.sh
. "$BIN_DIR/lib/mux.sh"   # Multiplexer-Adapter (tmux|zellij) — nie direkt tmux/zellij rufen
TOOLHUB="$(cd "$ENGINE_ROOT/.." && pwd)"
BOBIVERSE_CONFIG="${BOBIVERSE_CONFIG:-$HOME/.claude/bobiverse.json}"
BOBNET_URL="${BOBNET_URL:-http://localhost:3030}"
REGISTRY="${DEV_TEAM_REGISTRY:-$TOOLHUB/projects.registry.json}"
GUPPI_REGISTER="${GUPPI_REGISTER:-1}"
TZc="${DEV_TEAM_TZ:-Europe/Berlin}"

FAIL=0
pass() { printf '  ✓ %s\n' "$*"; }
warn() { printf '  ⚠ %s\n' "$*"; }
fail() { printf '  ✗ %s\n' "$*"; FAIL=$((FAIL+1)); }
skip() { printf '  ⊘ %s\n' "$*"; }

# env_value <env-datei> <VAR> — liest `export VAR="..."` aus einer dev-team.env (ohne sie zu sourcen).
env_value() {
  [ -f "$1" ] || return 0
  sed -n "s/^export $2=\"\{0,1\}\([^\"]*\)\"\{0,1\}.*/\1/p" "$1" | head -n1
}

# expand_tilde <pfad> — Registry/env speichern ~ ggf. literal.
expand_tilde() { case "$1" in "~"/*) printf '%s' "$HOME/${1#\~/}";; *) printf '%s' "$1";; esac; }

# json_field <datei> <feld> — Top-Level-JSON-Feld (jq-frei).
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

# reg_has_uid <uid> — 0 wenn die zentrale Registry diesen uid schon kennt, sonst 1.
reg_has_uid() {
  REG_FILE="$REGISTRY" REG_UID="$1" python3 - <<'PY'
import json, os, sys
try:
    with open(os.environ["REG_FILE"]) as fh:
        data = json.load(fh)
except Exception:
    sys.exit(1)
uid = os.environ["REG_UID"]
for p in data.get("projects", []) if isinstance(data, dict) else []:
    if isinstance(p, dict) and p.get("uid") == uid:
        sys.exit(0)
sys.exit(1)
PY
}

# PROJECT_ROOT / PROJECT_UID auflösen: Env > dev-team.env (relativ zu CWD oder PROJECT_ROOT) > CWD.
resolve_project() {
  PROJECT_ROOT="${PROJECT_ROOT:-$PWD}"
  # dev-team.env an der üblichen Stelle suchen.
  local envf="$PROJECT_ROOT/_dev_team/dev-team.env"
  [ -f "$envf" ] || envf="$PROJECT_ROOT/dev-team.env"
  if [ -f "$envf" ]; then
    local r u; r="$(env_value "$envf" PROJECT_ROOT)"; u="$(env_value "$envf" PROJECT_UID)"
    [ -n "$r" ] && PROJECT_ROOT="$(expand_tilde "$r")"
    [ -z "${PROJECT_UID:-}" ] && [ -n "$u" ] && PROJECT_UID="$u"
  fi
  PROJECT_UID="${PROJECT_UID:-}"
}

# ── Check 1: Prozess-/Schedule-Watch ───────────────────────────────────────────────────────────────
check_processes() {
  echo "[1/3] Prozess- / Schedule-Watch"
  local mux sessions
  mux="$(mux_backend 2>/dev/null)"
  if [ -n "$mux" ] && sessions="$(mux_list 2>/dev/null)" && [ -n "$sessions" ]; then
    pass "$mux-Sessions: $(printf '%s' "$sessions" | paste -sd' ' -)"
  else
    skip "kein Multiplexer (tmux/zellij) / keine Sessions"
  fi
  # cron-Einträge, die Engine-Scripts referenzieren (Schedule-Sichtbarkeit, kein Eingriff).
  if command -v crontab >/dev/null 2>&1 && crontab -l >/dev/null 2>&1; then
    local n; n="$(crontab -l 2>/dev/null | grep -cE 'cron-(standup|recap|health|bugcheck|colonel)|scut-' || true)"
    [ -z "$n" ] && n=0
    if [ "$n" -gt 0 ]; then pass "cron: $n Engine-Job(s) eingetragen"; else skip "cron: keine Engine-Jobs"; fi
  else
    skip "kein crontab / leer"
  fi
}

# ── Check 2: BobNet-Register-Check (idempotentes self-register via onboard) ──────────────────────────
check_bobnet_register() {
  echo "[2/3] BobNet-Register-Check"
  local bobnet_cfg sc=""
  bobnet_cfg="$(json_field "$BOBIVERSE_CONFIG" bobnet)"
  if command -v curl >/dev/null 2>&1; then
    sc="$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 "$BOBNET_URL" 2>/dev/null)"
  fi

  local bobnet_present=0
  if [ "$sc" = "200" ]; then bobnet_present=1
  elif [ -n "$bobnet_cfg" ] && [ "$bobnet_cfg" != "None" ] && [ "$bobnet_cfg" != "null" ]; then bobnet_present=1
  fi

  if [ "$bobnet_present" -eq 0 ]; then
    skip "kein BobNet (bobiverse.json bobnet=null, $BOBNET_URL nicht 200) — Projekt läuft ohne (PLAN §5)"
    return
  fi
  pass "BobNet vorhanden (cfg='${bobnet_cfg:-}' / $BOBNET_URL=${sc:-n/a})"

  if [ -z "${PROJECT_UID:-}" ]; then
    warn "BobNet da, aber PROJECT_UID nicht auflösbar — kann Registrierung nicht prüfen (dev-team.env?)"
    return
  fi

  if reg_has_uid "$PROJECT_UID"; then
    pass "Projekt '$PROJECT_UID' bereits in Registry ($REGISTRY)"
    return
  fi

  # Noch nicht registriert → self-register. NICHT den Upsert duplizieren: bin/onboard IST die Logik
  # (Baustein 6, idempotent + non-destruktiv). Wir rufen es nur für DIESES Projekt auf.
  if [ "$GUPPI_REGISTER" != "1" ]; then
    warn "Projekt '$PROJECT_UID' NICHT registriert — GUPPI_REGISTER=0, nur gemeldet (kein onboard)"
    return
  fi
  local onboard="$ENGINE_ROOT/bin/onboard"
  if [ ! -x "$onboard" ] && [ ! -f "$onboard" ]; then
    fail "self-register unmöglich: bin/onboard fehlt ($onboard) — an Team-Lead eskalieren"
    return
  fi
  echo "  → self-register via bin/onboard (idempotenter Registry-Upsert, Baustein 6)"
  if PROJECT_UID="$PROJECT_UID" DEV_TEAM_REGISTRY="$REGISTRY" \
       bash "$onboard" "$PROJECT_ROOT" 2>&1 | sed 's/^/    /'; then
    if reg_has_uid "$PROJECT_UID"; then
      pass "Projekt '$PROJECT_UID' jetzt registriert (self-register erfolgreich)"
    else
      fail "onboard lief, aber '$PROJECT_UID' steht nicht in der Registry — an Team-Lead eskalieren"
    fi
  else
    fail "bin/onboard fehlgeschlagen — self-register abgebrochen, an Team-Lead eskalieren"
  fi
}

# ── Check 3: SCUT-Input-Routing (knüpft an scut-router.sh an, baut nichts neu) ───────────────────────
# route_stream  — reicht stdin 1:1 an den bestehenden Router durch. KEINE eigene Routing-Logik.
route_stream() {
  local router="$BIN_DIR/scut-router.sh"
  if [ ! -f "$router" ]; then
    echo "guppi --route: scut-router.sh nicht gefunden ($router)" >&2; return 1
  fi
  # CONTEXT_UID + Registry an den Router weiterreichen (er kennt die Routing-Tabelle).
  CONTEXT_UID="${PROJECT_UID:-${CONTEXT_UID:-}}" DEV_TEAM_REGISTRY="$REGISTRY" \
    bash "$router"
}

check_routing_info() {
  echo "[3/3] SCUT-Input-Routing"
  local router="$BIN_DIR/scut-router.sh"
  if [ -f "$router" ]; then
    pass "Router angebunden: $router (Events via 'guppi.sh --route' / stdin durchreichen)"
  else
    fail "scut-router.sh fehlt ($router) — Routing nicht möglich, an Team-Lead eskalieren"
  fi
}

run_watch() {
  resolve_project
  local ts; ts="$(TZ="$TZc" date '+%Y-%m-%d %H:%M' 2>/dev/null || date '+%Y-%m-%d %H:%M')"
  echo "=== GUPPI — Projekt-Watch $ts (uid=${PROJECT_UID:-?}, root=$PROJECT_ROOT) ==="
  check_processes
  check_bobnet_register
  check_routing_info
  echo "--- GUPPI: $FAIL Problem(e) ---"
  [ "$FAIL" -eq 0 ] && return 0 || return 1
}

# ── Self-Test: mktemp-Fixtures, kein echter Prozess-/Netz-/Onboard-Effekt ────────────────────────────
self_test() {
  local tmp; tmp="$(mktemp -d "${TMPDIR:-/tmp}/guppi-test.XXXXXX")"
  trap "rm -rf '$tmp'" EXIT
  local fail=0
  check() { if eval "$2"; then printf '  ✓ %s\n' "$3"; else printf '  ✗ %s\n' "$3"; fail=1; fi; }

  # env_value: liest export VAR="..." korrekt.
  cat > "$tmp/dev-team.env" <<'ENV'
export PROJECT_UID="alpha"
export PROJECT_ROOT="/tmp/alpha-proj"
ENV
  local ev_uid ev_root
  ev_uid="$(env_value "$tmp/dev-team.env" PROJECT_UID)"
  ev_root="$(env_value "$tmp/dev-team.env" PROJECT_ROOT)"
  check x "[ \"$ev_uid\" = alpha ]" "env_value: PROJECT_UID (war '$ev_uid')"
  check x "[ \"$ev_root\" = /tmp/alpha-proj ]" "env_value: PROJECT_ROOT (war '$ev_root')"

  # json_field: bobnet=null → leer; engine lesbar.
  printf '%s\n' '{"engine":"/x","bobnet":null,"version":1}' > "$tmp/bobiverse.json"
  check x "[ -z \"$(json_field "$tmp/bobiverse.json" bobnet)\" ]" "json_field: bobnet=null → leer"
  check x "[ \"$(json_field "$tmp/bobiverse.json" engine)\" = /x ]" "json_field: engine lesbar"

  # reg_has_uid: kennt 'alpha', nicht 'ghost'.
  cat > "$tmp/registry.json" <<JSON
{"version":1,"projects":[{"uid":"alpha","name":"alpha","path":"$tmp/alpha"}]}
JSON
  REGISTRY="$tmp/registry.json"
  check x "REGISTRY=$tmp/registry.json reg_has_uid alpha" "reg_has_uid: kennt 'alpha'"
  check x "! ( REGISTRY=$tmp/registry.json reg_has_uid ghost )" "reg_has_uid: kennt 'ghost' NICHT"

  # check_bobnet_register: kein BobNet → ⊘, kein FAIL (Port ins Leere, bobnet=null).
  FAIL=0
  BOBIVERSE_CONFIG="$tmp/bobiverse.json" BOBNET_URL="http://127.0.0.1:1" \
    PROJECT_UID="alpha" REGISTRY="$tmp/registry.json" \
    check_bobnet_register >/dev/null 2>&1
  check x "[ \"$FAIL\" = 0 ]" "check_bobnet_register: kein BobNet → kein ✗ (optional)"

  # check_bobnet_register: BobNet 'da' (cfg-Pfad), uid bereits registriert → kein Onboard, kein FAIL.
  printf '%s\n' "{\"engine\":\"/x\",\"bobnet\":\"$tmp/bobnet\",\"version\":1}" > "$tmp/bobiverse-on.json"
  FAIL=0
  BOBIVERSE_CONFIG="$tmp/bobiverse-on.json" BOBNET_URL="http://127.0.0.1:1" \
    PROJECT_UID="alpha" REGISTRY="$tmp/registry.json" GUPPI_REGISTER=1 \
    check_bobnet_register >/dev/null 2>&1
  check x "[ \"$FAIL\" = 0 ]" "check_bobnet_register: BobNet da + schon registriert → kein Onboard, kein ✗"

  # check_bobnet_register: BobNet da, uid NICHT registriert, GUPPI_REGISTER=0 → ⚠, kein FAIL, KEIN onboard.
  FAIL=0
  BOBIVERSE_CONFIG="$tmp/bobiverse-on.json" BOBNET_URL="http://127.0.0.1:1" \
    PROJECT_UID="ghost" REGISTRY="$tmp/registry.json" GUPPI_REGISTER=0 \
    check_bobnet_register >/dev/null 2>&1
  check x "[ \"$FAIL\" = 0 ]" "check_bobnet_register: nicht registriert + REGISTER=0 → ⚠ (kein onboard, kein ✗)"
  check x "! ( REGISTRY=$tmp/registry.json reg_has_uid ghost )" "REGISTER=0: 'ghost' NICHT in Registry geschrieben"

  # route_stream: reicht an scut-router.sh durch (dry-run, kein echter Inbox-Write).
  # Wir prüfen nur, dass der Router angesprochen wird (Router hat eigenen Self-Test) — hier
  # genügt, dass die Anbindung existiert.
  check x "[ -f \"$BIN_DIR/scut-router.sh\" ]" "Router-Anbindung vorhanden (scut-router.sh da)"

  if [ "$fail" = 0 ]; then echo "guppi self-test: GRÜN"; return 0
  else echo "guppi self-test: ROT"; return 1; fi
}

case "${1:-}" in
  --self-test|self-test) self_test; exit $? ;;
  --route|route)
    shift
    resolve_project
    if [ -n "${1:-}" ] && [ -f "$1" ]; then route_stream < "$1"; else route_stream; fi
    exit $? ;;
  ""|watch)              run_watch; exit $? ;;
  -h|--help)             sed -n '2,40p' "${BASH_SOURCE[0]}"; exit 0 ;;
  *) echo "Usage: guppi.sh [watch] | guppi.sh --route [file] | guppi.sh --self-test | guppi.sh --help" >&2; exit 64 ;;
esac
