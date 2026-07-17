#!/usr/bin/env bash
# hooks/deploy-guard.sh — PreToolUse-Guard für Deploy-/Production-/Secret-Pfade. Zweistufig:
#
#   BLOCK  (Exit 2)              : Production-/Secret-Pfade — Tier-4, {HUMAN}-only, Edit nie erlaubt.
#   ASK    (permissionDecision)  : Deploy-Configs (deploy.rb, config/deploy/*, Capfile,
#                                  configuration.yml) — Edit erlaubt, aber NUR mit {HUMAN}-
#                                  Bestätigung PRO Edit (Prompt, nie auto-accept/allow). Der Bob
#                                  EDITIERT, der {HUMAN} stimmt JEDEM Schritt zu. (PO 2026-06-15.)
#   ASK    (Befehl, opt-in)      : Deploy-BEFEHLE (Bash) — laufen nur nach {HUMAN}-Bestätigung
#                                  UND exakt nach dem definierten Ablauf. (§17, PO 2026-06-13.)
#
# Trigger : PreToolUse — Edit|Write|MultiEdit (Pfad-Stufen) · Bash (Befehl-Stufe). Siehe team-rules/hooks.md.
# Vertrag : Tool-JSON kommt auf stdin; wir ziehen file_path UND command jq-frei heraus.
# Regel   : Block-Globs aus team-rules/deploy-guard.paths, Ask-Globs aus
#           team-rules/deploy-guard.ask.paths — je: Engine-Datei (oder eingebauter Fallback) IMMER
#           geladen + Projekt-Override ERGÄNZT nur (additiv, kann die Engine-Liste nie verdrängen).
#           Command-Globs aus team-rules/deploy-guard.commands (opt-in, KEIN Floor) +
#           Ablauf-Text aus team-rules/deploy-guard.procedure (Projekt-Override > Engine-Default).
# Ausgang : Exit 2 + Hinweis auf stderr = BLOCK · JSON {"permissionDecision":"ask"} auf stdout
#           + Exit 0 = Bestätigungs-Pflicht · sonst Exit 0 = durchlassen.
#
# Daten vor Code: KEINE hartkodierten Projekt-Pfade — Globs leben in team-rules/*.paths.
# Block schlägt Ask: ein Override darf nur ERWEITERN/verschärfen (ask→block ok), nie lockern.
# Floor-Fix (2026-07-17, Kanon-Drift #1): vorher konnte ein Projekt-Override die ENGINE-Liste
# komplett ERSETZEN (nur die 5 t4_floor-Secrets-Globs waren wirklich unbedingt). Jetzt ist die
# ganze Engine-Liste (Secrets + recipes2go + Production-Infra) der Floor — Override ergänzt nur.
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

# --- Glob-Listen laden: Engine-Datei = Floor (IMMER geladen) + Projekt-Override = additiv ---
# (vorher: Projekt-Override > Engine > Defaults — ein Override ersetzte damit die Engine-Liste
# komplett statt sie nur zu ergänzen. Fix 2026-07-17, Kanon-Drift #1.)
ENGINE_PATHS_FILE=""
[ -f "$ENGINE_ROOT/team-rules/deploy-guard.paths" ] && ENGINE_PATHS_FILE="$ENGINE_ROOT/team-rules/deploy-guard.paths"
PROJECT_PATHS_FILE=""
[ -n "${PROJECT_ROOT:-}" ] && [ -f "${PROJECT_ROOT}/_dev_team/team-rules/deploy-guard.paths" ] \
  && PROJECT_PATHS_FILE="${PROJECT_ROOT}/_dev_team/team-rules/deploy-guard.paths"

ENGINE_ASK_PATHS_FILE=""
[ -f "$ENGINE_ROOT/team-rules/deploy-guard.ask.paths" ] && ENGINE_ASK_PATHS_FILE="$ENGINE_ROOT/team-rules/deploy-guard.ask.paths"
PROJECT_ASK_PATHS_FILE=""
[ -n "${PROJECT_ROOT:-}" ] && [ -f "${PROJECT_ROOT}/_dev_team/team-rules/deploy-guard.ask.paths" ] \
  && PROJECT_ASK_PATHS_FILE="${PROJECT_ROOT}/_dev_team/team-rules/deploy-guard.ask.paths"

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
  # Engine-Datei = Floor, IMMER geladen (fehlt sie ganz, greift t4_floor() weiter unten als
  # letzte Instanz). Projekt-Datei ist rein ADDITIV — kann die Engine-Liste nie verdrängen,
  # nur erweitern (Floor-Fix 2026-07-17, Kanon-Drift #1, s. Kopf-Kommentar).
  [ -n "$ENGINE_PATHS_FILE" ] && grep -vE '^[[:space:]]*(#|$)' "$ENGINE_PATHS_FILE"
  [ -n "$PROJECT_PATHS_FILE" ] && grep -vE '^[[:space:]]*(#|$)' "$PROJECT_PATHS_FILE"
}

load_ask_globs() {
  [ -n "$ENGINE_ASK_PATHS_FILE" ] && grep -vE '^[[:space:]]*(#|$)' "$ENGINE_ASK_PATHS_FILE"
  [ -n "$PROJECT_ASK_PATHS_FILE" ] && grep -vE '^[[:space:]]*(#|$)' "$PROJECT_ASK_PATHS_FILE"
}

# --- T4-Floor (BLOCK): nicht-überschreibbare Kern-Globs (Production/Secrets, {HUMAN}-only) ---
# Werden IMMER geprüft — auch wenn ein Projekt-Override sie weglässt. T4 ist Floor, nicht Ceiling.
# Hardcodiert (nicht aus einer Datei gelesen) als LETZTE Instanz: greift selbst dann noch, wenn
# die Engine-eigene team-rules/deploy-guard.paths komplett fehlt (kaputte/unvollständige
# Installation) — deshalb auch hier die vollständige Liste, nicht nur die Secret-Kern-Globs
# (Kanon-Drift #1: die "breiteren" Production-Infra-Globs dürfen nirgends nur von EINER Quelle
# abhängen).
t4_floor() {
  cat <<'FLOOR'
*/.secrets/*
*master.key
*/config/master.key
*credentials.yml.enc
*.env.production
*recipes2go*
*/nginx/*production*
*docker-compose.prod*
*/k8s/production/*
FLOOR
}

# --- Ask-Floor: Deploy-Configs = bestätigungspflichtig PRO Edit (ask), NIE frei (PO 2026-06-15). ---
# Der Bob editiert, der {HUMAN} stimmt jedem Edit zu. Floor = nicht-überschreibbar (kein allow/acceptEdits).
ask_floor() {
  cat <<'FLOOR'
*/config/deploy.rb
*/config/deploy/*
*Capfile
*configuration.yml
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
  # JSON-sicher: erst Backslash, dann Anführungszeichen; danach ALLE Control-Chars
  # (0x01–0x1f, inkl. Tab/CR/NL/VT/FF) → Space. Sonst bräche ein roher Control-Char im
  # projekt-gelieferten procedure-Text die JSON-Ausgabe (Härtung, Review 2026-06-13).
  msg="${msg//\\/\\\\}"
  msg="${msg//\"/\\\"}"
  msg="${msg//[$'\x01'-$'\x1f']/ }"
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
      echo "  Liste: ${ENGINE_PATHS_FILE:-<eingebauter T4-Floor>}${PROJECT_PATHS_FILE:+ + $PROJECT_PATHS_FILE} — erweitern (additiv) via _dev_team/team-rules/deploy-guard.paths." >&2
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
