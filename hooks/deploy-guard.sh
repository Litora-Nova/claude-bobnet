#!/usr/bin/env bash
# hooks/deploy-guard.sh — PreToolUse-Guard: blockt Edits an Deploy-/Production-/Secret-Pfaden.
#
# Trigger : PreToolUse (Edit | Write | MultiEdit) — siehe team-rules/hooks.md.
# Vertrag : Tool-JSON kommt auf stdin; wir ziehen file_path jq-frei heraus.
# Regel   : Glob-Liste aus team-rules/deploy-guard.paths (Fallback: eingebaute Defaults).
# Ausgang : Exit 2 + Hinweis auf stderr = BLOCK (Tier-4, {HUMAN}-only). Sonst Exit 0 = durchlassen.
#
# Daten vor Code: KEINE hartkodierten Projekt-Pfade — Globs leben in team-rules/deploy-guard.paths.
set -uo pipefail

# --- Engine-ROOT relativ zum Script ableiten (kein hartkodierter Pfad) ---
HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENGINE_ROOT="$(cd "$HOOK_DIR/.." && pwd)"

# --- Optional dev-team.env sourcen (für PROJECT_ROOT-Override der Daten-Datei) ---
for env_candidate in \
  "${DEV_TEAM_ENV:-}" \
  "$ENGINE_ROOT/scripts/dev-team.env" \
  "$ENGINE_ROOT/../../_dev_team/dev-team.env"; do
  [ -n "$env_candidate" ] && [ -f "$env_candidate" ] && { . "$env_candidate"; break; }
done

# --- Glob-Liste laden: Projekt-Override > Engine-Daten > eingebaute Defaults ---
PATHS_FILE=""
for cand in \
  "${PROJECT_ROOT:-}/_dev_team/team-rules/deploy-guard.paths" \
  "$ENGINE_ROOT/team-rules/deploy-guard.paths"; do
  [ -n "$cand" ] && [ -f "$cand" ] && { PATHS_FILE="$cand"; break; }
done

load_globs() {
  if [ -n "$PATHS_FILE" ]; then
    # Kommentare + Leerzeilen raus
    grep -vE '^[[:space:]]*(#|$)' "$PATHS_FILE"
  else
    # Fallback-Defaults (spiegeln team-rules/deploy-guard.paths)
    cat <<'DEFAULTS'
*/config/deploy.rb
*/config/deploy/*
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

# --- file_path aus stdin-JSON ziehen (jq-frei; greift "file_path":"..." ab) ---
payload="$(cat 2>/dev/null || true)"
file_path="$(printf '%s' "$payload" \
  | grep -oE '"file_path"[[:space:]]*:[[:space:]]*"[^"]*"' \
  | head -n1 \
  | sed -E 's/.*"file_path"[[:space:]]*:[[:space:]]*"([^"]*)".*/\1/')"

# Kein file_path → nichts zu prüfen, durchlassen (fail-open für Nicht-Datei-Tools).
[ -z "$file_path" ] && exit 0

# --- T4-Floor: nicht-überschreibbare Kern-Globs (Production/Secrets, {HUMAN}-only) ---
# Werden IMMER geprüft — auch wenn ein Projekt-Override sie weglässt. T4 ist Floor, nicht Ceiling.
t4_floor() {
  cat <<'FLOOR'
*/.secrets/*
*master.key
*/config/master.key
*credentials.yml.enc
*.env.production
*/config/deploy/*
*/config/deploy.rb
*Capfile
*configuration.yml
FLOOR
}

# --- Match: jede Glob (Override/Defaults + T4-Floor) gegen den file_path (bash [[ == ]] Glob-Semantik) ---
while IFS= read -r glob; do
  [ -z "$glob" ] && continue
  # shellcheck disable=SC2053
  if [[ "$file_path" == $glob ]]; then
    echo "deploy-guard: BLOCKED — '$file_path' matcht geschützte Glob '$glob'." >&2
    echo "  Deploy-/Production-/Secret-Pfade sind Tier-4 ({HUMAN}-only). Edit nicht erlaubt." >&2
    echo "  Liste: ${PATHS_FILE:-<eingebaute Defaults>} (+ T4-Floor) — erweitern via team-rules/deploy-guard.paths." >&2
    exit 2
  fi
done < <(load_globs; t4_floor)

exit 0
