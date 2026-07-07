#!/usr/bin/env bash
# scripts/lib/spawn.sh — Provider-spezifischer Spawn-Command-Builder (ai-bobnet).
#
# Wandelt ein abstraktes "Starte Bob <archetype>" in einen konkreten CLI-Befehl um.
# Unterstuetzt Claude, Devin, Codex und Cursor. Cursor-CLI-Syntax ist noch ein Stub
# und muss an die tatsaechliche Cursor-CLI angepasst werden.
#
# Nutzung (sourcen):
#   . scripts/lib/spawn.sh
#   spawn_cmd claude backend "bash scripts/start-backend.sh"
#   # -> claude --model sonnet -- bash scripts/start-backend.sh
#
#   BOBNET_PROVIDER=devin spawn_cmd "" backend "bash scripts/start-backend.sh"
#   # -> devin --model swe-1-6 -- bash scripts/start-backend.sh

_SPAWN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$_SPAWN_DIR/model.sh"

# Unterstuetzte Provider und ihre Default-Binary-Namen.
# Cursor ist hier als CLI-Stub hinterlegt; tatsaechliche Syntax kann abweichen.
spawn_binary() {
  local provider="${1:-${BOBNET_PROVIDER:-claude}}"
  case "$provider" in
    claude) echo "claude" ;;
    devin)  echo "devin" ;;
    codex)  echo "codex" ;;
    cursor) echo "cursor" ;;
    *) echo "spawn_binary: unbekannter Provider '$provider'" >&2; return 2 ;;
  esac
}

# spawn_cmd [provider] <archetype_id> <start_cmd>
#   -> "<binary> <model-flag> -- <start_cmd>"
#   provider optional; default = BOBNET_PROVIDER oder claude
spawn_cmd() {
  local provider archetype start_cmd
  if [ $# -eq 3 ]; then
    provider="$1"; archetype="$2"; start_cmd="$3"
  else
    provider="${BOBNET_PROVIDER:-claude}"; archetype="$1"; start_cmd="$2"
  fi
  [ -n "$archetype" ] || { echo "spawn_cmd: archetype_id fehlt" >&2; return 2; }
  [ -n "$start_cmd" ] || { echo "spawn_cmd: start_cmd fehlt" >&2; return 2; }

  local binary flags
  binary="$(spawn_binary "$provider")" || return $?
  flags="$(model_flags --provider "$provider" "$archetype")" || return $?

  case "$provider" in
    claude|devin|codex)
      printf '%s %s -- %s\n' "$binary" "$flags" "$start_cmd"
      ;;
    cursor)
      # Cursor-CLI-Syntax ist noch nicht final; Stub mit Agent-Flag.
      printf '%s agent %s -- %s\n' "$binary" "$flags" "$start_cmd"
      ;;
  esac
}

# spawn_models <provider> — debug: alle Archetypen mit Modell auflisten
spawn_models() {
  local provider="${1:-${BOBNET_PROVIDER:-claude}}"
  for f in "$BOBNET_ARCHETYPES"/*.json; do
    [ -f "$f" ] || continue
    local id; id="$(basename "$f" .json)"
    printf '%s: %s\n' "$id" "$(model_resolve --provider "$provider" --full "$id")"
  done
}

# CLI-Entry
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  case "${1:-}" in
    --binary) shift; spawn_binary "$@" ;;
    --models) shift; spawn_models "$@" ;;
    "") echo "usage: spawn.sh [--binary <provider>] [--models <provider>] <provider> <archetype> <start_cmd>" >&2; exit 2 ;;
    *) spawn_cmd "$@" ;;
  esac
fi
