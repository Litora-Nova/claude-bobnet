#!/usr/bin/env bash
# git-identity.sh — resolved die Commit-Identität eines Agenten aus theme.json + dev-team.env.
#
# Regel-Quelle: team-rules/commits.md (Daten vor Code). Format:
#   <Name> (<Projekt-Display> <role>) <DEV_TEAM_EMAIL>
#
# Resolution (siehe commits.md):
#   NAME    = team.config members[].name (per-Team-Override, gewinnt)
#             | theme.json personas[<id>].name         (id = THEME_AGENT_ID | reverse-lookup HEARTBEAT_AGENT)
#             Reverse-Lookup-Kette für HEARTBEAT_AGENT: Theme-Persona-Name → team.config member.name
#             (so committet ein per-Team benannter Lead — z.B. "Martin" statt Theme-"Bob" — korrekt).
#   ROLE    = theme.json personas[<id>].positionLabel  (i18n -> en) | archetypes/<arch>.positionLong | ""
#   DISPLAY = dev-team.env PROJECT_NAME
#   EMAIL   = dev-team.env DEV_TEAM_EMAIL               (Default team@litora-nova.com)
#
# Usage:
#   git-identity.sh print                 # eine Zeile: "<Name> (<Display> <role>) <email>"
#   git-identity.sh export                # GIT_AUTHOR_*/GIT_COMMITTER_*-Exports (eval-bar)
#   git-identity.sh trailer               # "Co-Authored-By: <Name> (<Display> <role>) <email>"
#   git-identity.sh --self-test           # ohne Repo-Effekt; baut ein Demo-Theme/-Env, prüft alle Modi
#
# Env (alle optional, NIE Hardcode im Script):
#   THEME_AGENT_ID    exakter Persona-Key (z.B. BOB-dashboard). Höchste Prio.
#   HEARTBEAT_AGENT   Persona-NAME (z.B. Garfield) — Fallback-Lookup (vom Heartbeat-Hook ohnehin gesetzt).
#   THEME             Theme-Slug (Default: aus dev-team.env THEME, sonst "bobiverse").
#   THEMES_DIR        Externes Themes-Verzeichnis (user-seitig, z.B. eigenes Theme-Repo).
#                     Suchreihenfolge: $THEMES_DIR/<THEME>/ → $ENGINE_ROOT/themes/<THEME>/.
#                     (Pendant zum Dashboard-NUXT_THEMES_DIR — Themes wohnen beim User.)
#   TEAM_CONFIG       Pfad zur team.config.json (Default: $STANDUP_DIR/team.config.json) —
#                     Quelle des per-Team-Namens-Override (members[].name, keyed by id).
#   ENGINE_ROOT       Engine-Repo-Root (Default: 2 Ebenen über diesem Script).
#   DEV_TEAM_ENV      Pfad zur dev-team.env (Default: $PROJECT_ROOT/_dev_team/dev-team.env, sonst gesucht).
#   COMMIT_IDENTITY_MODE  author|trailer|both — steuert export-Verhalten (Default author).
#   DEV_TEAM_LOCALE   de|en — welche i18n-Variante des positionLabel (Default en).
set -uo pipefail

BIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENGINE_ROOT="${ENGINE_ROOT:-$(cd "$BIN_DIR/.." && pwd)}"

# --- dev-team.env finden + sourcen (für PROJECT_NAME / DEV_TEAM_EMAIL / THEME) ---
resolve_env_file() {
  if [ -n "${DEV_TEAM_ENV:-}" ] && [ -f "$DEV_TEAM_ENV" ]; then printf '%s' "$DEV_TEAM_ENV"; return; fi
  if [ -n "${PROJECT_ROOT:-}" ] && [ -f "$PROJECT_ROOT/_dev_team/dev-team.env" ]; then
    printf '%s' "$PROJECT_ROOT/_dev_team/dev-team.env"; return
  fi
  # Heuristik: relativ zum CWD nach oben (max 4 Ebenen) eine _dev_team/dev-team.env suchen.
  local d="$PWD"
  for _ in 1 2 3 4; do
    [ -f "$d/_dev_team/dev-team.env" ] && { printf '%s' "$d/_dev_team/dev-team.env"; return; }
    d="$(dirname "$d")"
  done
  printf ''
}

ENV_FILE="$(resolve_env_file)"
if [ -n "$ENV_FILE" ] && [ -f "$ENV_FILE" ]; then
  # shellcheck disable=SC1090
  set -a; . "$ENV_FILE"; set +a
fi

THEME="${THEME:-bobiverse}"
# Theme-Suchpfad: externes User-Themes-Verzeichnis (THEMES_DIR) schlägt Engine-Builtins.
THEME_JSON="$ENGINE_ROOT/themes/$THEME/theme.json"
if [ -n "${THEMES_DIR:-}" ] && [ -f "$THEMES_DIR/$THEME/theme.json" ]; then
  THEME_JSON="$THEMES_DIR/$THEME/theme.json"
fi
# team.config (per-Team-Namens-Override): explizit > Standup-Konvention.
if [ -z "${TEAM_CONFIG:-}" ] && [ -n "${STANDUP_DIR:-}" ] && [ -f "$STANDUP_DIR/team.config.json" ]; then
  TEAM_CONFIG="$STANDUP_DIR/team.config.json"
fi
ARCHETYPES_DIR="$ENGINE_ROOT/archetypes"
DEV_TEAM_EMAIL="${DEV_TEAM_EMAIL:-team@litora-nova.com}"
PROJECT_DISPLAY="${PROJECT_NAME:-}"
LOCALE="${DEV_TEAM_LOCALE:-en}"
MODE="${COMMIT_IDENTITY_MODE:-author}"

# --- Identität via python3 resolven (jq-frei, konsistent mit onboard/launcher) ---
# Gibt bei Erfolg "NAME\tROLE" aus, sonst leer + Warnung auf stderr.
resolve_identity() {
  THEME_JSON="$THEME_JSON" ARCHETYPES_DIR="$ARCHETYPES_DIR" TEAM_CONFIG_JSON="${TEAM_CONFIG:-}" \
  THEME_AGENT_ID="${THEME_AGENT_ID:-}" HEARTBEAT_AGENT="${HEARTBEAT_AGENT:-}" LOCALE="$LOCALE" \
  python3 - <<'PY'
import json, os, sys, glob

theme_path = os.environ["THEME_JSON"]
arch_dir   = os.environ["ARCHETYPES_DIR"]
want_id    = os.environ.get("THEME_AGENT_ID", "").strip()
want_name  = os.environ.get("HEARTBEAT_AGENT", "").strip()
locale     = os.environ.get("LOCALE", "en")

# team.config members (per-Team-Namens-Override; optional, fail-safe)
members = []
tc_path = os.environ.get("TEAM_CONFIG_JSON", "").strip()
if tc_path and os.path.isfile(tc_path):
    try:
        with open(tc_path) as fh:
            members = json.load(fh).get("members") or []
    except Exception as exc:
        sys.stderr.write("git-identity: WARN team.config nicht lesbar (%s): %s\n" % (tc_path, exc))
members = [m for m in members if isinstance(m, dict)]

try:
    with open(theme_path) as fh:
        theme = json.load(fh)
except Exception as exc:
    sys.stderr.write("git-identity: theme.json nicht lesbar (%s): %s\n" % (theme_path, exc))
    sys.exit(1)

personas = theme.get("personas", {})
if not isinstance(personas, dict) or not personas:
    sys.stderr.write("git-identity: theme.json hat keine personas\n")
    sys.exit(1)

pid, persona, member = None, None, None
if want_id:
    persona = personas.get(want_id)
    if persona is None:
        sys.stderr.write("git-identity: THEME_AGENT_ID '%s' nicht im Theme\n" % want_id)
        sys.exit(2)
    pid = want_id
    member = next((m for m in members if m.get("id") == pid), None)
elif want_name:
    matches = [(k, v) for k, v in personas.items()
               if isinstance(v, dict) and v.get("name") == want_name]
    if matches:
        if len(matches) > 1:
            sys.stderr.write("git-identity: WARN name='%s' mehrfach — nehme '%s'\n"
                             % (want_name, matches[0][0]))
        pid, persona = matches[0]
    else:
        # Fallback: per-Team benannter Agent (team.config member.name → id → Theme-Rolle).
        member = next((m for m in members
                       if (m.get("name") or "").strip() == want_name and m.get("id")), None)
        if member is None:
            sys.stderr.write("git-identity: kein Persona mit name='%s' im Theme '%s' (und kein team.config-Member)\n"
                             % (want_name, theme.get("id", "?")))
            sys.exit(2)
        pid = member["id"]
        persona = personas.get(pid) or {}
else:
    sys.stderr.write("git-identity: weder THEME_AGENT_ID noch HEARTBEAT_AGENT gesetzt\n")
    sys.exit(2)

# Per-Team-Override gewinnt: team.config member.name > Theme-Persona-Name.
name = ((member or {}).get("name") or persona.get("name") or "").strip()
if not name:
    sys.stderr.write("git-identity: persona '%s' hat keinen name\n" % pid)
    sys.exit(2)

def i18n_pick(val):
    if isinstance(val, dict):
        return (val.get(locale) or val.get("en") or val.get("de") or "").strip()
    return (val or "").strip()

role = i18n_pick(persona.get("positionLabel"))

# Fallback: positionLong aus dem Archetyp, dessen idPattern == pid.
if not role and os.path.isdir(arch_dir):
    for f in sorted(glob.glob(os.path.join(arch_dir, "*.json"))):
        try:
            with open(f) as fh:
                arch = json.load(fh)
        except Exception:
            continue
        if arch.get("idPattern") == pid:
            role = (arch.get("positionLong") or arch.get("positionShort") or "").strip()
            break

sys.stdout.write("%s\t%s" % (name, role))
PY
}

build_identity_line() {
  local name="$1" role="$2"
  if [ -z "$PROJECT_DISPLAY" ]; then
    echo "git-identity: WARN PROJECT_NAME (Display) leer — dev-team.env fehlt/unvollständig" >&2
    PROJECT_DISPLAY="?"
  fi
  if [ -n "$role" ]; then
    printf '%s (%s %s) <%s>' "$name" "$PROJECT_DISPLAY" "$role" "$DEV_TEAM_EMAIL"
  else
    printf '%s (%s) <%s>' "$name" "$PROJECT_DISPLAY" "$DEV_TEAM_EMAIL"
  fi
}

# Liefert über globale NAME/ROLE; rc!=0 = nicht auflösbar (fail-safe).
load() {
  local out; out="$(resolve_identity)" || return $?
  NAME="${out%%$'\t'*}"
  ROLE="${out#*$'\t'}"
  [ "$ROLE" = "$out" ] && ROLE=""   # kein Tab => kein role
  [ -n "$NAME" ]
}

cmd_print() {
  load || { echo "git-identity: Identität nicht auflösbar" >&2; return 1; }
  build_identity_line "$NAME" "$ROLE"; echo
}

# dq_quote <wert> — eval-sicher in doppelte Anführungszeichen verpacken. Bewusst NICHT `%q`:
# `%q` backslash-escaped Spaces/Klammern (Garfield\ \(...\)), wodurch der Wert zwar eval-bar bleibt,
# aber der lesbare Roh-Name (mit echten Spaces) nicht mehr als Substring auftaucht — die Specs
# (und ein Mensch, der das `export …` liest) erwarten "Garfield (Display Role)" wörtlich. Innerhalb
# von "…" sind Spaces/Klammern in bash unkritisch; nur " ` $ \ müssen escaped werden.
dq_quote() {
  local s="$1"
  s="${s//\\/\\\\}"   # Backslash zuerst
  s="${s//\"/\\\"}"   # "
  s="${s//\`/\\\`}"   # `
  s="${s//\$/\\\$}"   # $
  printf '"%s"' "$s"
}

cmd_export() {
  if ! load; then
    echo "# git-identity: Identität nicht auflösbar — git-Default bleibt (kein Export)" >&2
    return 1
  fi
  local ident
  ident="$(build_identity_line "$NAME" "$ROLE")"
  local disp="$PROJECT_DISPLAY"
  local fullname
  if [ -n "$ROLE" ]; then fullname="$NAME ($disp $ROLE)"; else fullname="$NAME ($disp)"; fi
  case "$MODE" in
    author|both)
      printf 'export GIT_AUTHOR_NAME=%s\n'    "$(dq_quote "$fullname")"
      printf 'export GIT_COMMITTER_NAME=%s\n' "$(dq_quote "$fullname")"
      printf 'export GIT_AUTHOR_EMAIL=%s\n'    "$(dq_quote "$DEV_TEAM_EMAIL")"
      printf 'export GIT_COMMITTER_EMAIL=%s\n' "$(dq_quote "$DEV_TEAM_EMAIL")"
      ;;
  esac
  case "$MODE" in
    trailer|both)
      printf 'export GIT_COMMIT_TRAILER=%s\n' "$(dq_quote "Co-Authored-By: $ident")"
      ;;
  esac
}

cmd_trailer() {
  load || { echo "git-identity: Identität nicht auflösbar" >&2; return 1; }
  printf 'Co-Authored-By: %s\n' "$(build_identity_line "$NAME" "$ROLE")"
}

cmd_self_test() {
  # Baut ein Wegwerf-Theme + dev-team.env in /tmp, prüft alle 3 Modi gegen erwartete Werte.
  # EXIT- statt RETURN-Trap: der RETURN-Trap-Befehl (rm) kann unter `set -o pipefail` den
  # Funktions-Return-Status verschleiern → Self-Test meldete „ROT", Script exitete aber 0.
  # Mit EXIT-Trap + explizitem `exit` (siehe case unten) propagiert der Status zuverlässig.
  local tmp; tmp="$(mktemp -d "${TMPDIR:-/tmp}/git-identity-test.XXXXXX")"
  # ${tmp:-}: der EXIT-Trap feuert NACH Funktions-Ende — `local tmp` ist dann weg (set -u).
  trap 'rm -rf "${tmp:-}"' EXIT
  mkdir -p "$tmp/themes/demo" "$tmp/archetypes"
  cat > "$tmp/themes/demo/theme.json" <<'JSON'
{ "id":"demo","label":"Demo","defaultAvatar":"default.png",
  "personas":{
    "BOB-dashboard":{"name":"Garfield","positionLabel":{"de":"BobNet Architekt","en":"BobNet Architect"}},
    "BOB-backend":{"name":"Bill"}
  } }
JSON
  cat > "$tmp/archetypes/backend.json" <<'JSON'
{ "archetype":"backend","positionLong":"Backend + Infra","idPattern":"BOB-backend" }
JSON
  cat > "$tmp/env" <<'ENV'
export PROJECT_NAME="Claude-tools"
export DEV_TEAM_EMAIL="team@litora-nova.com"
ENV

  local fail=0
  run() { ENGINE_ROOT="$tmp" DEV_TEAM_ENV="$tmp/env" THEME=demo "$BIN_DIR/git-identity.sh" "$@"; }
  check() { # <desc> <got> <want>
    if [ "$2" = "$3" ]; then printf '  ✓ %s\n' "$1"
    else printf '  ✗ %s\n     got:  %s\n     want: %s\n' "$1" "$2" "$3"; fail=1; fi
  }

  # 1) print per HEARTBEAT_AGENT (Name-Lookup) + i18n positionLabel en
  check "print (name-lookup, i18n en)" \
    "$(HEARTBEAT_AGENT=Garfield run print)" \
    "Garfield (Claude-tools BobNet Architect) <team@litora-nova.com>"
  # 2) print per THEME_AGENT_ID (exakt)
  check "print (id-lookup)" \
    "$(THEME_AGENT_ID=BOB-dashboard run print)" \
    "Garfield (Claude-tools BobNet Architect) <team@litora-nova.com>"
  # 3) role-Fallback aus Archetyp positionLong (Bill hat kein positionLabel)
  check "print (role-fallback positionLong)" \
    "$(HEARTBEAT_AGENT=Bill run print)" \
    "Bill (Claude-tools Backend + Infra) <team@litora-nova.com>"
  # 4) trailer-Modus
  check "trailer" \
    "$(HEARTBEAT_AGENT=Garfield run trailer)" \
    "Co-Authored-By: Garfield (Claude-tools BobNet Architect) <team@litora-nova.com>"
  # 5) export (author) enthält den Full-Name + Email
  local exp; exp="$(HEARTBEAT_AGENT=Garfield COMMIT_IDENTITY_MODE=author run export)"
  case "$exp" in
    *"GIT_AUTHOR_NAME="*"Garfield (Claude-tools BobNet Architect)"*"GIT_AUTHOR_EMAIL="*"team@litora-nova.com"*)
      printf '  ✓ export author (name+email)\n';;
    *) printf '  ✗ export author — unerwartet:\n%s\n' "$exp"; fail=1;;
  esac
  # 6) i18n de
  check "print (i18n de)" \
    "$(HEARTBEAT_AGENT=Garfield DEV_TEAM_LOCALE=de run print)" \
    "Garfield (Claude-tools BobNet Architekt) <team@litora-nova.com>"
  # 7) fail-safe: unbekannter Name -> rc!=0, keine Zeile
  if HEARTBEAT_AGENT=Niemand run print >/dev/null 2>&1; then
    printf '  ✗ fail-safe (unbekannter Name sollte rc!=0 geben)\n'; fail=1
  else
    printf '  ✓ fail-safe (unbekannter Name -> rc!=0)\n'
  fi

  if [ "$fail" = 0 ]; then echo "git-identity self-test: GRÜN"; return 0
  else echo "git-identity self-test: ROT"; return 1; fi
}

case "${1:-print}" in
  print)        cmd_print ;;
  export)       cmd_export ;;
  trailer)      cmd_trailer ;;
  --self-test|self-test) cmd_self_test; exit $? ;;
  *) echo "Usage: git-identity.sh {print|export|trailer|--self-test}" >&2; exit 64 ;;
esac
