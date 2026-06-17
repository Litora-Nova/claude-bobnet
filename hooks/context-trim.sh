#!/usr/bin/env bash
# hooks/context-trim.sh — PostToolUse-Hook-Entrypoint (Token-Win). Löst die Schwellen-Config auf
# (Projekt-Override > Engine > Defaults) und reicht stdin (das Tool-JSON) an hooks/context-trim.py.
#
# Trigger : PostToolUse (Bash|Read|MCP-Tools) — siehe team-rules/hooks.md.
# Vertrag : Tool-JSON kommt auf stdin; das Python kürzt das größte Text-Feld übergroßer Outputs,
#           stasht den Volltext, lässt alles andere unangetastet. FAIL-SAFE: kein python3, kein
#           Treffer, jeder Fehler → pass-through (nichts auf stdout → Original-Output bleibt).
# Daten vor Code: Schwellen in team-rules/context-trim.conf, Mechanik im Python.
set -uo pipefail

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENGINE_ROOT="$(cd "$HOOK_DIR/.." && pwd)"

# Optional dev-team.env sourcen (für PROJECT_ROOT-Override der Config)
for env_candidate in \
  "${DEV_TEAM_ENV:-}" \
  "$ENGINE_ROOT/scripts/dev-team.env" \
  "$ENGINE_ROOT/../../_dev_team/dev-team.env"; do
  [ -n "$env_candidate" ] && [ -f "$env_candidate" ] && { . "$env_candidate"; break; }
done

# Config laden: Projekt-Override > Engine. set -a → alle gesetzten KEYs werden exportiert.
for conf in \
  "${PROJECT_ROOT:-}/_dev_team/team-rules/context-trim.conf" \
  "$ENGINE_ROOT/team-rules/context-trim.conf"; do
  [ -n "$conf" ] && [ -f "$conf" ] && { set -a; . "$conf"; set +a; break; }
done

# Stash-Default, falls die Config ihn nicht setzt (ephemer, NICHT in ein Repo)
: "${CT_STASH_DIR:=${TMPDIR:-/tmp}/bobnet-context-trim}"
export CT_STASH_DIR

# Fail-safe: ohne python3 nichts tun → Original-Output bleibt unverändert
command -v python3 >/dev/null 2>&1 || exit 0

exec python3 "$HOOK_DIR/context-trim.py"
