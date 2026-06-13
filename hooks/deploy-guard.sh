#!/usr/bin/env bash
# hooks/deploy-guard.sh — PreToolUse-Guard für Deploy-/Production-/Secret-Pfade. Zweistufig:
#
#   BLOCK  (Exit 2)              : Production-/Secret-Pfade — Tier-4, {HUMAN}-only, Edit nie erlaubt.
#   ASK    (permissionDecision)  : Deploy-Configs — Edit erlaubt, aber NUR mit expliziter
#                                  {HUMAN}-Bestätigung PRO Edit (nie auto-accept). Keine
#                                  strukturellen Umbauten. (PO-Doktrin 2026-06-10, tiers.md.)
#   ASK    (Befehl, opt-in)      : Deploy-BEFEHLE (Bash) — laufen nur nach {HUMAN}-Bestätigung
#                                  UND exakt nach dem definierten Ablauf. (§17, PO 2026-06-13.)
#
# Trigger : PreToolUse — Edit|Write|MultiEdit (Pfad-Stufen) · Bash (Befehl-Stufe). Siehe team-rules/hooks.md.
# Vertrag : Tool-JSON kommt auf stdin; wir ziehen file_path UND command jq-frei heraus.
# Regel   : Block-Globs aus team-rules/deploy-guard.paths, Ask-Globs aus
#           team-rules/deploy-guard.ask.paths (je: Projekt-Override > Engine > eingebauter Floor).
#           Command-Globs aus team-rules/deploy-guard.commands (opt-in, KEIN Floor) +
#           Ablauf-Text aus team-rules/deploy-guard.procedure (Projekt-Override > Engine-Default).
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

COMMANDS_FILE=""
for cand in \
  "${PROJECT_ROOT:-}/_dev_team/team-rules/deploy-guard.commands" \
  "$ENGINE_ROOT/team-rules/deploy-guard.commands"; do
  [ -n "$cand" ] && [ -f "$cand" ] && { COMMANDS_FILE="$cand"; break; }
done

PROCEDURE_FILE=""
for cand in \
  "${PROJECT_ROOT:-}/_dev_team/team-rules/deploy-guard.procedure" \
  "$ENGINE_ROOT/team-rules/deploy-guard.procedure"; do
  [ -n "$cand" ] && [ -f "$cand" ] && { PROCEDURE_FILE="$cand"; break; }
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

# --- Command-Globs laden (opt-in: KEIN Floor, KEINE Fallback-Defaults) ---
# Ohne Datei/Override = keine Command-Asks. Unbeteiligte Projekte bleiben unbehelligt.
load_command_globs() {
  [ -n "$COMMANDS_FILE" ] && grep -vE '^[[:space:]]*(#|$)' "$COMMANDS_FILE"
}

# --- Bestätigungs-Hinweis für Deploy-Befehle bauen (Basis + erzwungener Ablauf, JSON-sicher) ---
build_command_reason() {
  local base proc msg line
  base="deploy-guard: Deploy-Befehl erkannt — nur mit ausdrücklicher {HUMAN}-Bestätigung ausführen, exakt nach dem definierten Ablauf (team-rules/tiers.md, §17)"
  proc=""
  if [ -n "$PROCEDURE_FILE" ]; then
    while IFS= read -r line; do
      [ -z "$line" ] && continue
      if [ -z "$proc" ]; then proc="$line"; else proc="$proc; $line"; fi
    done < <(grep -vE '^[[:space:]]*(#|$)' "$PROCEDURE_FILE")
  fi
  msg="$base"
  [ -n "$proc" ] && msg="$base — Ablauf: $proc"
  # JSON-sicher: erst Backslash, dann Anführungszeichen; Tab/CR neutralisieren.
  msg="${msg//\\/\\\\}"
  msg="${msg//\"/\\\"}"
  msg="${msg//$'\t'/ }"
  msg="${msg//$'\r'/}"
  printf '%s' "$msg"
}

# --- file_path UND command aus stdin-JSON ziehen (jq-frei) ---
payload="$(cat 2>/dev/null || true)"
file_path="$(printf '%s' "$payload" \
  | grep -oE '"file_path"[[:space:]]*:[[:space:]]*"[^"]*"' \
  | head -n1 \
  | sed -E 's/.*"file_path"[[:space:]]*:[[:space:]]*"([^"]*)".*/\1/')"
# command-String (Bash-Tool); stoppt am ersten internen '"' — für die Glob-Treffer
# unkritisch (Deploy-Verb steht früh) und immer in die sichere Richtung "ask".
command_str="$(printf '%s' "$payload" \
  | grep -oE '"command"[[:space:]]*:[[:space:]]*"[^"]*"' \
  | head -n1 \
  | sed -E 's/.*"command"[[:space:]]*:[[:space:]]*"([^"]*)".*/\1/')"

# Weder Datei noch Befehl → nichts zu prüfen, durchlassen (fail-open für Nicht-Ziel-Tools).
[ -z "$file_path" ] && [ -z "$command_str" ] && exit 0

# === Pfad-getriebene Stufen (Edit|Write|MultiEdit) ===
if [ -n "$file_path" ]; then
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

  # --- Stufe 2 — ASK (Pfad): Deploy-Configs erzwingen die {HUMAN}-Bestätigung pro Edit ---
  while IFS= read -r glob; do
    [ -z "$glob" ] && continue
    # shellcheck disable=SC2053
    if [[ "$file_path" == $glob ]]; then
      safe_path="${file_path//\"/}"
      printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"ask","permissionDecisionReason":"deploy-guard: %s ist Deploy-Config — Edit nur mit expliziter Bestätigung pro Edit, keine strukturellen Umbauten (team-rules/tiers.md)."}}\n' "$safe_path"
      exit 0
    fi
  done < <(load_ask_globs; ask_floor)
fi

# === Command-getriebene Stufe (Bash) — opt-in, nur wenn KEIN file_path (echtes Bash-Tool) ===
if [ -z "$file_path" ] && [ -n "$command_str" ]; then
  while IFS= read -r glob; do
    [ -z "$glob" ] && continue
    # shellcheck disable=SC2053
    if [[ "$command_str" == *$glob* ]]; then
      printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"ask","permissionDecisionReason":"%s"}}\n' "$(build_command_reason)"
      exit 0
    fi
  done < <(load_command_globs)
fi

exit 0
