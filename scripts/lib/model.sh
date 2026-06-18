#!/usr/bin/env bash
# scripts/lib/model.sh — config-driven Model+Effort-Resolver pro Rolle (Issue #36).
#
# Warum: Verschiedene Rollen verdienen verschiedene Model-Tiers + Denk-Budgets. Statt
# per-Prompt-Hacks lebt das Default in archetypes/<id>.json (Felder `model` + `effort`),
# am Boot/Spawn gelesen — und durch die Instanz (team.config / Env) UEBERSCHREIBBAR.
# Der Lead reicht das Ergebnis beim Spawn weiter (Agent-Tool model/effort bzw. claude --model).
#
# Aufloesung (Praezedenz, hoechste zuerst):
#   1. Env-Override   BOBNET_MODEL_OVERRIDE / BOBNET_EFFORT_OVERRIDE  (Instanz/team.config-Hook)
#   2. Archetyp       archetypes/<id>.json: .model / .effort
#   3. Fallback aus   .modelTier  (HEAVEN->opus/high · Cruiser->sonnet/medium · Probe->haiku/low)
#
# Nutzung:
#   source scripts/lib/model.sh; model_resolve techlead   # -> "opus xhigh"
#   scripts/lib/model.sh backend                          # CLI: "opus xhigh"
#   scripts/lib/model.sh --model backend                  # CLI: "--model opus" (fuer claude-CLI-Spawns)
#
# jq-frei (python3), konsistent mit scripts/git-identity.sh / onboard.

_model_lib_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
: "${BOBNET_ARCHETYPES:=$_model_lib_dir/../../archetypes}"

# model_resolve <archetype_id>  ->  echoes "<model> <effort>" (rc 3 = kein Archetyp, 4 = unbestimmbar)
model_resolve() {
  local id="${1:-}"
  [ -n "$id" ] || { echo "model_resolve: archetype-id fehlt" >&2; return 2; }
  BOBNET_ARCHETYPES="$BOBNET_ARCHETYPES" \
  BOBNET_MODEL_OVERRIDE="${BOBNET_MODEL_OVERRIDE:-}" \
  BOBNET_EFFORT_OVERRIDE="${BOBNET_EFFORT_OVERRIDE:-}" \
  python3 - "$id" <<'PY'
import json, os, sys
arch_dir = os.environ["BOBNET_ARCHETYPES"]
aid = sys.argv[1]
path = os.path.join(arch_dir, aid + ".json")
TIER = {"HEAVEN": ("opus", "high"), "Cruiser": ("sonnet", "medium"), "Probe": ("haiku", "low")}
try:
    with open(path) as f:
        a = json.load(f)
except FileNotFoundError:
    print(f"model_resolve: kein Archetyp {path}", file=sys.stderr); sys.exit(3)
tm, te = TIER.get(a.get("modelTier"), (None, None))
model  = os.environ.get("BOBNET_MODEL_OVERRIDE")  or a.get("model")  or tm
effort = os.environ.get("BOBNET_EFFORT_OVERRIDE") or a.get("effort") or te
if not model or not effort:
    print(f"model_resolve: model/effort unbestimmbar fuer {aid} (model={model} effort={effort})", file=sys.stderr); sys.exit(4)
print(model, effort)
PY
}

# model_flags <archetype_id> -> "--model <model>" (effort separat via Env/Agent-Tool weitergereicht)
model_flags() {
  local out; out="$(model_resolve "$1")" || return $?
  printf -- '--model %s\n' "${out%% *}"
}

# CLI-Entry (nur wenn direkt ausgefuehrt, nicht beim source)
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  case "${1:-}" in
    --model) shift; model_flags "$@" ;;
    "")      echo "usage: model.sh [--model] <archetype_id>" >&2; exit 2 ;;
    *)       model_resolve "$@" ;;
  esac
fi
