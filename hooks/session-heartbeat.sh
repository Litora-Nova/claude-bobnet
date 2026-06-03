#!/usr/bin/env bash
# hooks/session-heartbeat.sh — SessionStart-Heartbeat des arbeitenden Agents.
#
# Trigger : SessionStart — siehe team-rules/hooks.md + team-rules/heartbeat.md.
# Zweck   : schreibt beim Session-Start einen Heartbeat (log.sh $AGENT busy "session-start")
#           in DAS BobNet (STANDUP_DIR) der Instanz, mit der diese Session zusammenarbeitet.
# Regel   : AGENT = HEARTBEAT_AGENT (cross-project shared Service, z.B. Garfield/GUPPI),
#           sonst Default = TEAM_LEAD (Lead-Session). STANDUP_DIR + Logger aus dev-team.env.
#           Deklarative Regel: team-rules/heartbeat.md.
# Ausgang : IMMER Exit 0. Fail-safe — blockt die Session NIE, auch wenn log.sh fehlt/fehlschlägt.
set -uo pipefail

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd 2>/dev/null)" || exit 0
ENGINE_ROOT="$(cd "$HOOK_DIR/.." && pwd 2>/dev/null)" || exit 0

# Env sourcen (für TEAM_LEAD / STANDUP_DIR). Still scheitern erlaubt.
for env_candidate in \
  "${DEV_TEAM_ENV:-}" \
  "$ENGINE_ROOT/scripts/dev-team.env" \
  "$ENGINE_ROOT/../../_dev_team/dev-team.env"; do
  if [ -n "$env_candidate" ] && [ -f "$env_candidate" ]; then
    # shellcheck disable=SC1090
    . "$env_candidate" 2>/dev/null || true
    break
  fi
done

# Wer heartbeatet: cross-project shared Service setzt HEARTBEAT_AGENT (z.B. Garfield/GUPPI),
# Lead-Session lässt es unset → Default = TEAM_LEAD. Rückwärtskompatibel (kein Bruch für acme-Bob).
AGENT="${HEARTBEAT_AGENT:-${TEAM_LEAD:-Bob}}"
LOGGER="$ENGINE_ROOT/scripts/log.sh"

# Fail-safe: Logger muss existieren + ausführbar sein, sonst still raus.
# STANDUP_DIR (aus dev-team.env) bestimmt, in WESSEN BobNet geloggt wird — log.sh respektiert es.
if [ -x "$LOGGER" ]; then
  "$LOGGER" "$AGENT" busy "session-start" 2>/dev/null || true
elif [ -f "$LOGGER" ]; then
  bash "$LOGGER" "$AGENT" busy "session-start" 2>/dev/null || true
fi

exit 0
