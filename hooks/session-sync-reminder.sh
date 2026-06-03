#!/usr/bin/env bash
# hooks/session-sync-reminder.sh — SessionStart-Reminder zur State-Sync-Disziplin.
#
# Trigger : SessionStart — siehe team-rules/hooks.md.
# Regel   : Reminder-Text kommt aus team-rules/sync.md (REMINDER:-Block) + Env-Token-Ersatz.
# Ausgang : druckt den Reminder auf stdout, Exit 0. Fail-safe — blockt die Session NIE.
#
# Daten vor Code: KEIN hartkodierter Reminder-Text — die Vorlage lebt in team-rules/sync.md.
set -uo pipefail

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENGINE_ROOT="$(cd "$HOOK_DIR/.." && pwd)"

# Env sourcen (für PROJECT_NAME / CANONICAL_BRANCH / DEV_TEAM_REPOS / PROJECT_ROOT).
for env_candidate in \
  "${DEV_TEAM_ENV:-}" \
  "$ENGINE_ROOT/scripts/dev-team.env" \
  "$ENGINE_ROOT/../../_dev_team/dev-team.env"; do
  [ -n "$env_candidate" ] && [ -f "$env_candidate" ] && { . "$env_candidate"; break; }
done

# Defaults, falls Env-Keys fehlen.
PROJECT_NAME="${PROJECT_NAME:-dieses Projekt}"
CANONICAL_BRANCH="${CANONICAL_BRANCH:-master}"
DEV_TEAM_REPOS="${DEV_TEAM_REPOS:-.}"

# Daten-Datei: Projekt-Override > Engine-Default.
SYNC_FILE=""
for cand in \
  "${PROJECT_ROOT:-}/_dev_team/team-rules/sync.md" \
  "$ENGINE_ROOT/team-rules/sync.md"; do
  [ -n "$cand" ] && [ -f "$cand" ] && { SYNC_FILE="$cand"; break; }
done

# REMINDER:-Block aus der Daten-Datei extrahieren (alles nach der "REMINDER:"-Zeile).
render() {
  if [ -n "$SYNC_FILE" ]; then
    awk 'f{print} /^REMINDER:/{f=1}' "$SYNC_FILE"
  else
    # Fallback, falls sync.md fehlt.
    cat <<'FALLBACK'
🔄 Sync-Reminder ({PROJECT_NAME}) — Session-Start
  • Branch-Check: auf {CANONICAL_BRANCH}? lokal == origin?
  • Repos syncen (fetch → pull → push): {DEV_TEAM_REPOS}
  → `bin/sync` erledigt das über alle Repos.
FALLBACK
  fi
}

# Token-Ersatz (sed-frei am String, damit Sonderzeichen in Werten safe sind).
text="$(render)"
text="${text//\{PROJECT_NAME\}/$PROJECT_NAME}"
text="${text//\{CANONICAL_BRANCH\}/$CANONICAL_BRANCH}"
text="${text//\{DEV_TEAM_REPOS\}/$DEV_TEAM_REPOS}"

printf '%s\n' "$text"
exit 0
