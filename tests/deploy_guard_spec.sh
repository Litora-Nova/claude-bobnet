#!/usr/bin/env bash
# tests/deploy_guard_spec.sh — Black-Box-Spec für hooks/deploy-guard.sh.
#
# Spec-Quelle: team-rules/tiers.md („Push- & Deploy-Leitplanken" + „T4 = nicht-überschreibbarer
# Floor", PO-Doktrin 2026-06-15) + die Header von deploy-guard.paths / deploy-guard.ask.paths:
#   - Secret-/Production-Pfade  → BLOCK (Exit 2), nicht override-bar (t4_floor); inkl. recipes2go.
#   - Deploy-Configs (deploy.rb, config/deploy/*, Capfile, configuration.yml)
#                               → ASK (permissionDecision "ask", Exit 0), nicht unterschreitbar
#                                 (ask_floor), aber per Projekt-Override verschärfbar (ask→block).
#   - alles andere              → durchlassen (Exit 0, kein Output).
#
# Kanon-Drift-Fix #1 (README-Sync 2026-07-17): die Engine-eigene team-rules/deploy-guard.paths
# (bzw. deploy-guard.ask.paths) wird jetzt IMMER geladen; ein Projekt-Override ist rein ADDITIV
# (kann nur erweitern, nie ersetzen). Vorher konnte ein Projekt-Override, der die Engine-Liste
# komplett ersetzte, die "breiteren" Production-Infra-Globs (recipes2go, nginx/*production*,
# docker-compose.prod, k8s/production) unbemerkt verlieren — nur die 5 Secret-Kern-Globs waren
# über t4_floor() wirklich unbedingt. t4_floor() selbst deckt jetzt zusätzlich als LETZTE Instanz
# (fehlt die Engine-Datei ganz) auch die breiteren Globs ab.
. "$(dirname "${BASH_SOURCE[0]}")/_helper.sh"

HOOK="$ENGINE_ROOT/hooks/deploy-guard.sh"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
EMPTY_ENV="$TMP/empty.env"
: > "$EMPTY_ENV"

run_guard() { # $1 = file_path · $2 = PROJECT_ROOT (optional) → setzt GUARD_OUT + GUARD_RC
  GUARD_OUT="$(printf '{"tool_input":{"file_path":"%s"}}' "$1" \
    | DEV_TEAM_ENV="$EMPTY_ENV" PROJECT_ROOT="${2:-}" bash "$HOOK" 2>/dev/null)"
  GUARD_RC=$?
}

# JSON-Wohlgeformtheit jq-frei prüfen (python3 wenn da, sonst überspringen → kein false-fail).
is_json() {
  if command -v python3 >/dev/null 2>&1; then
    printf '%s' "$1" | python3 -c 'import sys,json; json.load(sys.stdin)' >/dev/null 2>&1
  else
    return 0  # ohne Parser nicht testbar; nicht als Fehler werten
  fi
}

echo "deploy_guard_spec:"

# --- Stufe BLOCK: Secrets/Struktur = Exit 2, kein ask-JSON ---
run_guard "/proj/.secrets/github_token"
it "blockt .secrets/ (Exit 2)";                eq "$GUARD_RC" "2"
run_guard "/proj/config/master.key"
it "blockt config/master.key (Exit 2)";        eq "$GUARD_RC" "2"
run_guard "/proj/config/credentials.yml.enc"
it "blockt credentials.yml.enc (Exit 2)";      eq "$GUARD_RC" "2"
run_guard "/proj/.env.production"
it "blockt .env.production (Exit 2)";          eq "$GUARD_RC" "2"
it "Block liefert KEIN ask-JSON";              not_contains "$GUARD_OUT" "permissionDecision"
run_guard "/proj/recipes2go/recipe.rb"
it "blockt recipes2go (shared gem, Exit 2)";   eq "$GUARD_RC" "2"

# --- Stufe ASK: Deploy-Configs = Exit 0 + permissionDecision "ask" ---
run_guard "/proj/config/deploy/staging.rb"
it "Stage-Config staging.rb → Exit 0";         eq "$GUARD_RC" "0"
it "Stage-Config staging.rb → ask";            contains "$GUARD_OUT" '"permissionDecision":"ask"'
run_guard "/proj/config/deploy/production.rb"
it "Stage-Config production.rb → ask";         contains "$GUARD_OUT" '"permissionDecision":"ask"'
run_guard "/proj/config/deploy.rb"
it "globale deploy.rb → Exit 0";               eq "$GUARD_RC" "0"
it "globale deploy.rb → ask";                  contains "$GUARD_OUT" '"permissionDecision":"ask"'
run_guard "/proj/config/deploy/templates/nginx.conf.erb"
it "Deploy-Template unter config/deploy/ → ask"; contains "$GUARD_OUT" '"permissionDecision":"ask"'
# Capfile + configuration.yml: BLOCK→ASK (PO-Doktrin 2026-06-15 — Bob editiert, {HUMAN} bestätigt pro Edit)
run_guard "/proj/Capfile"
it "Capfile → Exit 0 (PO 2026-06-15)";         eq "$GUARD_RC" "0"
it "Capfile → ask";                            contains "$GUARD_OUT" '"permissionDecision":"ask"'
run_guard "/proj/config/configuration.yml"
it "configuration.yml → Exit 0 (PO 2026-06-15)"; eq "$GUARD_RC" "0"
it "configuration.yml → ask";                  contains "$GUARD_OUT" '"permissionDecision":"ask"'

# --- Durchlassen: normale Dateien + fehlender file_path ---
run_guard "/proj/app/models/user.rb"
it "normale Datei → Exit 0";                   eq "$GUARD_RC" "0"
it "normale Datei → kein Output";              eq "$GUARD_OUT" ""
GUARD_OUT="$(printf '{"tool_name":"Edit"}' | DEV_TEAM_ENV="$EMPTY_ENV" bash "$HOOK" 2>/dev/null)"
GUARD_RC=$?
it "kein file_path → fail-open Exit 0";        eq "$GUARD_RC" "0"

# --- T4-Floor: Projekt-Override OHNE Secret-Globs blockt Secrets trotzdem ---
mkdir -p "$TMP/proj/_dev_team/team-rules"
printf '*/nur-eigene-glob/*\n' > "$TMP/proj/_dev_team/team-rules/deploy-guard.paths"
run_guard "/proj/.secrets/token" "$TMP/proj"
it "t4_floor: Override ohne Secrets blockt .secrets trotzdem (Exit 2)"; eq "$GUARD_RC" "2"
run_guard "/proj/nur-eigene-glob/datei.txt" "$TMP/proj"
it "Override-Glob erweitert den Block (Exit 2)"; eq "$GUARD_RC" "2"

# --- Additiver Merge-Nachweis unabhängig von t4_floor(): synthetische, T4-neutrale Globs ---
# Die Hook-Kopie leitet ENGINE_ROOT aus ihrem eigenen Speicherort ab; ein Environment-Override
# würde die echte Engine-Datei weiterverwenden und die getestete Datenquelle nicht isolieren.
FAKE_ENGINE_MERGE="$TMP/fake-engine-merge"
FAKE_PROJECT_MERGE="$TMP/fake-project-merge"
mkdir -p "$FAKE_ENGINE_MERGE/hooks" "$FAKE_ENGINE_MERGE/team-rules" \
  "$FAKE_PROJECT_MERGE/_dev_team/team-rules"
cp "$HOOK" "$FAKE_ENGINE_MERGE/hooks/deploy-guard.sh"
printf '*/engine-floor-sentinel/*\n' > "$FAKE_ENGINE_MERGE/team-rules/deploy-guard.paths"
printf '*/project-addon-sentinel/*\n' > "$FAKE_PROJECT_MERGE/_dev_team/team-rules/deploy-guard.paths"

run_merge_guard() { # $1 = file_path → setzt GUARD_OUT + GUARD_RC
  GUARD_OUT="$(printf '{"tool_input":{"file_path":"%s"}}' "$1" \
    | DEV_TEAM_ENV="$EMPTY_ENV" PROJECT_ROOT="$FAKE_PROJECT_MERGE" \
      bash "$FAKE_ENGINE_MERGE/hooks/deploy-guard.sh" 2>/dev/null)"
  GUARD_RC=$?
}

run_merge_guard "/proj/engine-floor-sentinel/datei.txt"
it "additiver Merge: Engine-Glob bleibt mit Projekt-Override aktiv"; eq "$GUARD_RC" "2"
run_merge_guard "/proj/project-addon-sentinel/datei.txt"
it "additiver Merge: Projekt-Glob erweitert die Engine-Liste";        eq "$GUARD_RC" "2"
run_merge_guard "/proj/neutral-sentinel/datei.txt"
it "additiver Merge: neutraler Pfad → Exit 0";                         eq "$GUARD_RC" "0"
it "additiver Merge: neutraler Pfad → kein Output";                    eq "$GUARD_OUT" ""

# --- Kanon-Drift #1 (README-Sync 2026-07-17): ein Projekt-Override, der die Engine-Liste
#     NICHT erwähnt, darf die "breiteren" Production-Infra-Globs (recipes2go, nginx/*production*,
#     docker-compose.prod, k8s/production) nicht verlieren — vorher waren NUR die 5 Secret-Globs
#     wirklich unbedingt (t4_floor), diese vier lebten nur in den überschreibbaren Defaults.
run_guard "/proj/recipes2go/recipe.rb" "$TMP/proj"
it "Kanon-Drift #1: Override ohne recipes2go blockt es trotzdem (Exit 2)"; eq "$GUARD_RC" "2"
run_guard "/proj/nginx/production.conf" "$TMP/proj"
it "Kanon-Drift #1: Override ohne nginx/*production* blockt es trotzdem (Exit 2)"; eq "$GUARD_RC" "2"
run_guard "/proj/docker-compose.prod.yml" "$TMP/proj"
it "Kanon-Drift #1: Override ohne docker-compose.prod blockt es trotzdem (Exit 2)"; eq "$GUARD_RC" "2"
run_guard "/proj/k8s/production/deployment.yml" "$TMP/proj"
it "Kanon-Drift #1: Override ohne k8s/production blockt es trotzdem (Exit 2)"; eq "$GUARD_RC" "2"

# --- Fehlende Engine-Datei komplett: t4_floor() alleine deckt jetzt auch die breiteren Globs ---
FAKE_ENGINE_BROAD="$TMP/fake-engine-broad"
mkdir -p "$FAKE_ENGINE_BROAD/hooks" "$FAKE_ENGINE_BROAD/team-rules"
cp "$HOOK" "$FAKE_ENGINE_BROAD/hooks/deploy-guard.sh"
GUARD_OUT="$(printf '{"tool_input":{"file_path":"/proj/k8s/production/deployment.yml"}}' \
  | ENGINE_ROOT="$FAKE_ENGINE_BROAD" DEV_TEAM_ENV="$EMPTY_ENV" bash "$FAKE_ENGINE_BROAD/hooks/deploy-guard.sh" 2>/dev/null)"
GUARD_RC=$?
it "Kanon-Drift #1: fehlende Engine-paths → t4_floor blockt k8s/production trotzdem (Exit 2)"; eq "$GUARD_RC" "2"

# --- Ask-Floor: leerer Projekt-Ask-Override → Deploy-Configs bleiben ask ---
: > "$TMP/proj/_dev_team/team-rules/deploy-guard.ask.paths"
run_guard "/proj/config/deploy/staging.rb" "$TMP/proj"
it "ask_floor: leerer Ask-Override → staging.rb bleibt ask"; contains "$GUARD_OUT" '"permissionDecision":"ask"'

# --- Verschärfen erlaubt: Projekt-Block-Override auf config/deploy/* schlägt Ask ---
printf '*/config/deploy/*\n' > "$TMP/proj/_dev_team/team-rules/deploy-guard.paths"
run_guard "/proj/config/deploy/staging.rb" "$TMP/proj"
it "Block schlägt Ask: Projekt darf ask→block verschärfen (Exit 2)"; eq "$GUARD_RC" "2"

# --- JSON-Wohlgeformtheit: ask-Output ist valides JSON mit dem erwarteten Decision-Feld ---
# (Die contains-Checks oben prüfen nur Substrings — eine kaputte Klammer würde durchrutschen.)
run_guard "/proj/config/deploy.rb"
it "ask-Output ist wohlgeformtes JSON";        ok is_json "$GUARD_OUT"
run_guard "/proj/config/deploy/staging.rb"
it "ask-JSON trägt hookEventName PreToolUse";  contains "$GUARD_OUT" '"hookEventName":"PreToolUse"'

# --- Engine-Ask-Datei FEHLT komplett → ask_floor muss trotzdem greifen (nicht fail-open) ---
# Eigenes, leeres Temp-Engine ohne deploy-guard.ask.paths; Hook von dort, ENGINE_ROOT zeigt drauf.
FAKE_ENGINE="$TMP/fake-engine"
mkdir -p "$FAKE_ENGINE/hooks" "$FAKE_ENGINE/team-rules"
cp "$HOOK" "$FAKE_ENGINE/hooks/deploy-guard.sh"
# bewusst KEINE *.paths-Dateien anlegen → Block-Defaults greifen, Ask hängt allein am Floor.
GUARD_OUT="$(printf '{"tool_input":{"file_path":"/proj/config/deploy/prod.rb"}}' \
  | ENGINE_ROOT="$FAKE_ENGINE" DEV_TEAM_ENV="$EMPTY_ENV" bash "$FAKE_ENGINE/hooks/deploy-guard.sh" 2>/dev/null)"
GUARD_RC=$?
it "fehlende Engine-ask.paths → ask_floor greift trotzdem (ask)"; contains "$GUARD_OUT" '"permissionDecision":"ask"'
it "fehlende Engine-ask.paths → Exit 0";        eq "$GUARD_RC" "0"
# … und der Block-Floor steht ebenfalls ohne Engine-Datei (Secret bleibt Exit 2):
printf '{"tool_input":{"file_path":"/proj/.secrets/x"}}' \
  | ENGINE_ROOT="$FAKE_ENGINE" DEV_TEAM_ENV="$EMPTY_ENV" bash "$FAKE_ENGINE/hooks/deploy-guard.sh" >/dev/null 2>&1
GUARD_RC=$?  # rc SOFORT sichern — 'it' liefe sonst dazwischen und überschriebe $?
it "fehlende Engine-paths → t4_floor blockt Secret trotzdem (Exit 2)"; eq "$GUARD_RC" "2"

# --- Tool-Vielfalt: file_path wird tool-unabhängig gezogen (Write/MultiEdit-Payload) ---
printf '{"tool_name":"MultiEdit","tool_input":{"file_path":"/proj/.secrets/x"}}' \
  | DEV_TEAM_ENV="$EMPTY_ENV" bash "$HOOK" >/dev/null 2>&1
GUARD_RC=$?
it "MultiEdit-Payload: Secret → Exit 2";       eq "$GUARD_RC" "2"
run_guard_write() { GUARD_OUT="$(printf '{"tool_name":"Write","tool_input":{"file_path":"%s","content":"x"}}' "$1" | DEV_TEAM_ENV="$EMPTY_ENV" bash "$HOOK" 2>/dev/null)"; GUARD_RC=$?; }
run_guard_write "/proj/config/deploy.rb"
it "Write-Payload mit content: deploy.rb → ask"; contains "$GUARD_OUT" '"permissionDecision":"ask"'

# --- Glob-Sonderfall: kein Match darf via fehlerhaftem Glob-Quoting passieren ---
# Pfad mit Glob-Metazeichen im Namen darf NICHT versehentlich matchen (durchlassen).
run_guard "/proj/app/[deploy].rb"
it "Pfad mit Glob-Metazeichen, kein echter Treffer → Exit 0"; eq "$GUARD_RC" "0"

# --- Block UND Ask treffen denselben Pfad → Block gewinnt (Reihenfolge im Hook) ---
# config/deploy/* ist Ask-Floor; via Engine-Default ist es NICHT Block — also über Projekt-Block triggern,
# während der Ask-Floor weiter aktiv ist. Ergebnis muss Exit 2 sein, KEIN ask-JSON.
printf '*/config/deploy/*\n' > "$TMP/proj/_dev_team/team-rules/deploy-guard.paths"
: > "$TMP/proj/_dev_team/team-rules/deploy-guard.ask.paths"  # ask via Floor weiter aktiv
run_guard "/proj/config/deploy/production.rb" "$TMP/proj"
it "Block UND Ask treffen → Block gewinnt (Exit 2)";       eq "$GUARD_RC" "2"
it "Block-Gewinn liefert KEIN ask-JSON";                   not_contains "$GUARD_OUT" "permissionDecision"

# --- Stufe ASK (Befehl, Bash): opt-in via Projekt-Override (§17, PO 2026-06-13) ---
run_guard_cmd() { # $1 = command · $2 = PROJECT_ROOT (optional) → setzt GUARD_OUT + GUARD_RC
  GUARD_OUT="$(printf '{"tool_name":"Bash","tool_input":{"command":"%s"}}' "$1" \
    | DEV_TEAM_ENV="$EMPTY_ENV" PROJECT_ROOT="${2:-}" bash "$HOOK" 2>/dev/null)"
  GUARD_RC=$?
}

# Engine-Default OHNE Override = keine Command-Asks (Beispiele in der Engine sind auskommentiert).
run_guard_cmd "bundle exec cap staging deploy"
it "Engine-Default (kein Override): Deploy-Befehl → kein ask"; not_contains "$GUARD_OUT" "permissionDecision"
it "Engine-Default: Deploy-Befehl → Exit 0";                   eq "$GUARD_RC" "0"

# Projekt schaltet die Bremse via Override scharf (commands + eigener procedure-Ablauf).
CMDPROJ="$TMP/cmdproj"
mkdir -p "$CMDPROJ/_dev_team/team-rules"
printf '*cap *deploy*\n' > "$CMDPROJ/_dev_team/team-rules/deploy-guard.commands"
printf 'Zuerst SSL/Zertifikat.\nDann Migrationen.\n' > "$CMDPROJ/_dev_team/team-rules/deploy-guard.procedure"

run_guard_cmd "bundle exec cap staging deploy" "$CMDPROJ"
it "Override aktiv: cap deploy → ask";           contains "$GUARD_OUT" '"permissionDecision":"ask"'
it "Override aktiv: cap deploy → Exit 0";        eq "$GUARD_RC" "0"
it "Command-ask trägt hookEventName PreToolUse"; contains "$GUARD_OUT" '"hookEventName":"PreToolUse"'
it "Command-ask ist wohlgeformtes JSON";         ok is_json "$GUARD_OUT"
it "Command-ask injiziert den Projekt-Ablauf";   contains "$GUARD_OUT" "Zuerst SSL/Zertifikat"

# Harmloser Befehl unter aktivem Override → durchlassen (kein Output, Exit 0).
run_guard_cmd "ls -la" "$CMDPROJ"
it "harmloser Befehl trotz Override → kein ask"; not_contains "$GUARD_OUT" "permissionDecision"
it "harmloser Befehl → Exit 0";                  eq "$GUARD_RC" "0"

# commands-Override OHNE procedure-Override → Engine-Default-Ablauf greift als Fallback.
CMDPROJ2="$TMP/cmdproj2"
mkdir -p "$CMDPROJ2/_dev_team/team-rules"
printf '*cap *deploy*\n' > "$CMDPROJ2/_dev_team/team-rules/deploy-guard.commands"
run_guard_cmd "cap production deploy" "$CMDPROJ2"
it "ohne procedure-Override → trotzdem ask";                 contains "$GUARD_OUT" '"permissionDecision":"ask"'
it "ohne procedure-Override → Engine-Default-Ablauf im ask"; contains "$GUARD_OUT" "Deploy nur nach ausdrücklicher Bestätigung"

# Härtung: roher Control-Char (VT/FF) im procedure-Text bricht das JSON NICHT (→ Space).
CMDPROJ3="$TMP/cmdproj3"
mkdir -p "$CMDPROJ3/_dev_team/team-rules"
printf '*cap *deploy*\n' > "$CMDPROJ3/_dev_team/team-rules/deploy-guard.commands"
printf 'Schritt mit \x0b VT und \x0c FF.\n' > "$CMDPROJ3/_dev_team/team-rules/deploy-guard.procedure"
run_guard_cmd "cap staging deploy" "$CMDPROJ3"
it "procedure mit Control-Chars → ask bleibt valides JSON"; ok is_json "$GUARD_OUT"
it "procedure mit Control-Chars → trotzdem ask";            contains "$GUARD_OUT" '"permissionDecision":"ask"'

# Trennung der Stufen: Command-Stufe greift NUR bei echtem Bash-Tool (kein file_path).
# Ein Write mit deploy-artigem Text im content darf NICHT via Command-Stufe asken.
GUARD_OUT="$(printf '{"tool_name":"Write","tool_input":{"file_path":"/proj/notes.txt","content":"cap staging deploy"}}' \
  | DEV_TEAM_ENV="$EMPTY_ENV" PROJECT_ROOT="$CMDPROJ" bash "$HOOK" 2>/dev/null)"; GUARD_RC=$?
it "Write mit deploy-Text im content → kein Command-ask"; not_contains "$GUARD_OUT" "permissionDecision"
it "Write normale Datei → Exit 0";                        eq "$GUARD_RC" "0"

summary
