#!/usr/bin/env bash
# hooks/deploy-guard.sh — PreToolUse-Guard für Deploy-/Production-/Secret-Pfade. Zweistufig:
#
#   BLOCK  (Exit 2)              : Production-/Secret-Pfade — Tier-4, {HUMAN}-only, Edit nie erlaubt.
#   ASK    (permissionDecision)  : Deploy-Configs — Edit erlaubt, aber NUR mit expliziter
#                                  {HUMAN}-Bestätigung PRO Edit (nie auto-accept). Keine
#                                  strukturellen Umbauten. (PO-Doktrin 2026-06-10, tiers.md.)
#
# Trigger : PreToolUse (Edit | Write | MultiEdit) — siehe team-rules/hooks.md.
# Vertrag : Tool-JSON kommt auf stdin; wir ziehen file_path jq-frei heraus.
# Regel   : Block-Globs aus team-rules/deploy-guard.paths, Ask-Globs aus
#           team-rules/deploy-guard.ask.paths (je: Projekt-Override > Engine > eingebauter Floor).
# Ausgang : Exit 2 + Hinweis auf stderr = BLOCK · JSON {"permissionDecision":"ask"} auf stdout
#           + Exit 0 = Bestätigungs-Pflicht · sonst Exit 0 = durchlassen.
#
# Daten vor Code: KEINE hartkodierten Projekt-Pfade — Globs leben in team-rules/*.paths.
# Block schlägt Ask: ein Override darf nur ERWEITERN/verschärfen (ask→block ok), nie lockern.
set -uo pipefail

# --- Engine-ROOT relativ zum Script ableiten (kein hartkodierter Pfad) ---
HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENGINE_ROOT="$(cd "$HOOK_DIR/.." && pwd)"

# --- Optional dev-team.env sourcen (für PROJECT_ROOT-Override der Daten-Dateien) ---
for env_candidate in \
  "${DEV_TEAM_ENV:-}" \
  "$ENGINE_ROOT/scripts/dev-team.env" \
  "$ENGINE_ROOT/../../_dev_team/dev-team.env"; do
  [ -n "$env_candidate" ] && [ -f "$env_candidate" ] && { . "$env_candidate"; break; }
done

# --- Glob-Listen laden: Projekt-Override > Engine-Daten > eingebaute Defaults ---
PATHS_FILE=""
for cand in \
  "${PROJECT_ROOT:-}/_dev_team/team-rules/deploy-guard.paths" \
  "$ENGINE_ROOT/team-rules/deploy-guard.paths"; do
  [ -n "$cand" ] && [ -f "$cand" ] && { PATHS_FILE="$cand"; break; }
done

ASK_PATHS_FILE=""
for cand in \
  "${PROJECT_ROOT:-}/_dev_team/team-rules/deploy-guard.ask.paths" \
  "$ENGINE_ROOT/team-rules/deploy-guard.ask.paths"; do
  [ -n "$cand" ] && [ -f "$cand" ] && { ASK_PATHS_FILE="$cand"; break; }
done

load_globs() {
  if [ -n "$PATHS_FILE" ]; then
    # Kommentare + Leerzeilen raus
    grep -vE '^[[:space:]]*(#|$)' "$PATHS_FILE"
  else
    # Fallback-Defaults (spiegeln team-rules/deploy-guard.paths)
    cat <<'DEFAULTS'
*/Capfile
*configuration.yml
*recipes2go*
*/.secrets/*
*credentials.yml.enc
*master.key
*.env.production
*/config/master.key
*/nginx/*production*
*docker-compose.prod*
*/k8s/production/*
DEFAULTS
  fi
}

load_ask_globs() {
  if [ -n "$ASK_PATHS_FILE" ]; then
    grep -vE '^[[:space:]]*(#|$)' "$ASK_PATHS_FILE"
  fi
}

# --- T4-Floor (BLOCK): nicht-überschreibbare Kern-Globs (Production/Secrets, {HUMAN}-only) ---
# Werden IMMER geprüft — auch wenn ein Projekt-Override sie weglässt. T4 ist Floor, nicht Ceiling.
t4_floor() {
  cat <<'FLOOR'
*/.secrets/*
*master.key
*/config/master.key
*credentials.yml.enc
*.env.production
*Capfile
*configuration.yml
FLOOR
}

# --- Ask-Floor: Deploy-Configs sind MINDESTENS bestätigungspflichtig (nie frei) ---
# Ein Projekt-Override darf sie zusätzlich BLOCKEN (strenger), aber nie freigeben.
ask_floor() {
  cat <<'FLOOR'
*/config/deploy.rb
*/config/deploy/*
FLOOR
}

# --- file_path aus stdin-JSON ziehen (jq-frei; greift "file_path":"..." ab) ---
payload="$(cat 2>/dev/null || true)"
file_path="$(printf '%s' "$payload" \
  | grep -oE '"file_path"[[:space:]]*:[[:space:]]*"[^"]*"' \
  | head -n1 \
  | sed -E 's/.*"file_path"[[:space:]]*:[[:space:]]*"([^"]*)".*/\1/')"

# Kein file_path → nichts zu prüfen, durchlassen (fail-open für Nicht-Datei-Tools).
[ -z "$file_path" ] && exit 0

# --- Stufe 1 — BLOCK: jede Block-Glob (Override/Defaults + T4-Floor) gegen den file_path ---
while IFS= read -r glob; do
  [ -z "$glob" ] && continue
  # shellcheck disable=SC2053
  if [[ "$file_path" == $glob ]]; then
    echo "deploy-guard: BLOCKED — '$file_path' matcht geschützte Glob '$glob'." >&2
    echo "  Production-/Secret-Pfade sind Tier-4 ({HUMAN}-only). Edit nicht erlaubt." >&2
    echo "  Liste: ${PATHS_FILE:-<eingebaute Defaults>} (+ T4-Floor) — erweitern via team-rules/deploy-guard.paths." >&2
    exit 2
  fi
done < <(load_globs; t4_floor)

# --- Stufe 2 — ASK: Deploy-Configs erzwingen die {HUMAN}-Bestätigung pro Edit ---
while IFS= read -r glob; do
  [ -z "$glob" ] && continue
  # shellcheck disable=SC2053
  if [[ "$file_path" == $glob ]]; then
    safe_path="${file_path//\"/}"
    printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"ask","permissionDecisionReason":"deploy-guard: %s ist Deploy-Config — Edit nur mit expliziter Bestätigung pro Edit, keine strukturellen Umbauten (team-rules/tiers.md)."}}\n' "$safe_path"
    exit 0
  fi
done < <(load_ask_globs; ask_floor)

exit 0
