#!/usr/bin/env bash
# tests/deploy_guard_spec.sh — Black-Box-Spec für hooks/deploy-guard.sh.
#
# Spec-Quelle: team-rules/tiers.md („Push- & Deploy-Leitplanken" + „T4 = nicht-überschreibbarer
# Floor", PO-Doktrin 2026-06-10) + die Header von deploy-guard.paths / deploy-guard.ask.paths:
#   - Production-/Secret-Pfade  → BLOCK (Exit 2), nicht override-bar (t4_floor).
#   - Deploy-Configs            → ASK (permissionDecision "ask", Exit 0), nicht unterschreitbar
#                                 (ask_floor), aber per Projekt-Override verschärfbar (ask→block).
#   - alles andere              → durchlassen (Exit 0, kein Output).
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
run_guard "/proj/Capfile"
it "blockt Capfile (Exit 2)";                  eq "$GUARD_RC" "2"
run_guard "/proj/config/configuration.yml"
it "blockt configuration.yml (Exit 2)";        eq "$GUARD_RC" "2"
it "Block liefert KEIN ask-JSON";              not_contains "$GUARD_OUT" "permissionDecision"

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

# --- Ask-Floor: leerer Projekt-Ask-Override → Deploy-Configs bleiben ask ---
: > "$TMP/proj/_dev_team/team-rules/deploy-guard.ask.paths"
run_guard "/proj/config/deploy/staging.rb" "$TMP/proj"
it "ask_floor: leerer Ask-Override → staging.rb bleibt ask"; contains "$GUARD_OUT" '"permissionDecision":"ask"'

# --- Verschärfen erlaubt: Projekt-Block-Override auf config/deploy/* schlägt Ask ---
printf '*/config/deploy/*\n' > "$TMP/proj/_dev_team/team-rules/deploy-guard.paths"
run_guard "/proj/config/deploy/staging.rb" "$TMP/proj"
it "Block schlägt Ask: Projekt darf ask→block verschärfen (Exit 2)"; eq "$GUARD_RC" "2"

summary
