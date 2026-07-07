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
#   # -> devin --model swe-1-6 -- bash scripts/start-backend.sh   (interaktiv)
#   # -> devin --model swe-1-6 -p "..."                         (non-interaktiv)
#
# Devin-Spezialfall:
#   Der Devin CLI kennt keinen Headless-Tool-Modus. --permission-mode bypass
#   scheitert ohne TTY/Scrollback ("Scrollback error: io error") und haengt
#   bei komplexen Aufgaben. Daher:
#   - Interaktiv: `devin --model <model> -- <start_cmd>`
#   - Non-Interactive: `devin --model <model> -p "<prompt>"` (nur Text, keine Tools)
#   - Fuer Non-Interactive Tool-Ausfuehrung: `devin-subagent` verwenden
#     (wrapped via Devin-Subagent-Tool / run_subagent).

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
#   -> "<binary> <model-flag> -- <start_cmd>" (claude/codex/cursor)
#   -> "<binary> <model-flag> -- <start_cmd>" (devin interaktiv)
#   -> "<binary> <model-flag> -p <prompt>"     (devin non-interaktiv)
#   provider optional; default = BOBNET_PROVIDER oder claude
#   Env: BOBNET_PROVIDER, BOBNET_NON_INTERACTIVE=(true|false)
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

  local non_interactive="${BOBNET_NON_INTERACTIVE:-}"
  # Nur auto-detect wenn die Env nicht explizit gesetzt wurde.
  if [ -z "$non_interactive" ]; then
    [ -t 0 ] || non_interactive="true"
  fi

  case "$provider" in
    claude|codex)
      printf '%s %s -- %s\n' "$binary" "$flags" "$start_cmd"
      ;;
    devin)
      if [ "$non_interactive" = "true" ]; then
        # Non-Interactive: Devin CLI kann hier keine Tools ausfuehren.
        # Wir nutzen -p fuer eine einzelne Antwort. Fuer Tool-Ausfuehrung
        # siehe Provider `devin-subagent`.
        printf '%s %s -p "You are %s. Task: %s. Reply with a short confirmation."\n' \
          "$binary" "$flags" "$archetype" "$start_cmd"
      else
        printf '%s %s -- %s\n' "$binary" "$flags" "$start_cmd"
      fi
      ;;
    cursor)
      # Cursor-CLI-Syntax ist noch nicht final; Stub mit Agent-Flag.
      printf '%s agent %s -- %s\n' "$binary" "$flags" "$start_cmd"
      ;;
  esac
}

# spawn_subagent_task [provider] <archetype_id> <start_cmd>
#   Liefert eine Task-Beschreibung, die an das Devin run_subagent-Tool uebergeben
#   werden kann. Nur fuer Provider `devin-subagent` sinnvoll.
spawn_subagent_task() {
  local provider archetype start_cmd
  if [ $# -eq 3 ]; then
    provider="$1"; archetype="$2"; start_cmd="$3"
  else
    provider="${BOBNET_PROVIDER:-claude}"; archetype="$1"; start_cmd="$2"
  fi
  [ -n "$archetype" ] || { echo "spawn_subagent_task: archetype_id fehlt" >&2; return 2; }
  [ -n "$start_cmd" ] || { echo "spawn_subagent_task: start_cmd fehlt" >&2; return 2; }

  local full
  full="$(model_resolve --provider devin --full "$archetype")" || return $?
  printf 'You are the %s (model: %s). Your task: %s\n' "$archetype" "$full" "$start_cmd"
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
    --subagent-task) shift; spawn_subagent_task "$@" ;;
    "") echo "usage: spawn.sh [--binary <provider>] [--models <provider>] [--subagent-task <provider> <archetype> <start_cmd>] <provider> <archetype> <start_cmd>" >&2; exit 2 ;;
    *) spawn_cmd "$@" ;;
  esac
fi
