#!/usr/bin/env bash
# scripts/lib/model.sh — config-driven Model+Effort-Resolver pro Rolle (Issue #36).
# Erweitert fuer ai-bobnet: Provider-Support (claude, devin, codex, cursor).
#
# Warum: Verschiedene Rollen verdienen verschiedene Model-Tiers + Denk-Budgets. Statt
# per-Prompt-Hacks lebt das Default in archetypes/<id>.json (Felder `model` + `effort`
# oder provider-spezifisch in `providers.<provider>`), am Boot/Spawn gelesen — und durch
# die Instanz (team.config / Env) UEBERSCHREIBBAR.
#
# Aufloesung (Praezedenz, hoechste zuerst):
#   1. Env-Override   BOBNET_MODEL_OVERRIDE / BOBNET_EFFORT_OVERRIDE
#   2. Provider-Config archetypes/<id>.json: providers.<provider>.model / .effort
#   3. Top-Level      archetypes/<id>.json: .model / .effort
#   4. Fallback       .modelTier (HEAVEN->opus/high · Cruiser->sonnet/medium · Probe->haiku/low)
#
# Nutzung:
#   source scripts/lib/model.sh; model_resolve techlead           # -> "opus xhigh" (default claude)
#   BOBNET_PROVIDER=devin model_resolve backend                   # -> "swe-1-6 high"
#   model_resolve --full backend                                  # -> "claude sonnet xhigh"
#   model.sh --model backend                                      # -> "--model sonnet"
#   model.sh --provider devin --model backend                     # -> "--model swe-1-6"
#
# jq-frei (python3), konsistent mit scripts/git-identity.sh / onboard.

_model_lib_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
: "${BOBNET_ARCHETYPES:=$_model_lib_dir/../../archetypes}"
: "${BOBNET_PROVIDER:=claude}"

# model_resolve [ --provider <name> ] [ --full ] <archetype_id>
#   -> "<model> <effort>" (oder mit --full: "<provider> <model> <effort>")
#   rc 2 = Option/Archetype-ID fehlt, 3 = kein Archetyp, 4 = unbestimmbar
model_resolve() {
  local _full=0 id=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --provider) BOBNET_PROVIDER="$2"; shift 2 ;;
      --full) _full=1; shift ;;
      --) shift; break ;;
      -*) echo "model_resolve: unbekannte Option $1" >&2; return 2 ;;
      *) id="$1"; break ;;
    esac
  done
  [ -n "$id" ] || { echo "model_resolve: archetype-id fehlt" >&2; return 2; }

  BOBNET_ARCHETYPES="$BOBNET_ARCHETYPES" \
  BOBNET_PROVIDER="${BOBNET_PROVIDER}" \
  BOBNET_MODEL_OVERRIDE="${BOBNET_MODEL_OVERRIDE:-}" \
  BOBNET_EFFORT_OVERRIDE="${BOBNET_EFFORT_OVERRIDE:-}" \
  python3 - "$id" "$_full" <<'PY'
import json, os, sys
arch_dir = os.environ["BOBNET_ARCHETYPES"]
provider = os.environ.get("BOBNET_PROVIDER", "claude")
aid = sys.argv[1]
full = sys.argv[2] == "1"
path = os.path.join(arch_dir, aid + ".json")
TIER = {"HEAVEN": ("opus", "high"), "Cruiser": ("sonnet", "medium"), "Probe": ("haiku", "low")}
try:
    with open(path) as f:
        a = json.load(f)
except FileNotFoundError:
    print(f"model_resolve: kein Archetyp {path}", file=sys.stderr); sys.exit(3)

pc = (a.get("providers") or {}).get(provider) or {}
tm, te = TIER.get(a.get("modelTier"), (None, None))
model  = os.environ.get("BOBNET_MODEL_OVERRIDE")  or pc.get("model")  or a.get("model")  or tm
effort = os.environ.get("BOBNET_EFFORT_OVERRIDE") or pc.get("effort") or a.get("effort") or te
if not model or not effort:
    print(f"model_resolve: model/effort unbestimmbar fuer {aid}/{provider} (model={model} effort={effort})", file=sys.stderr); sys.exit(4)
if full:
    print(provider, model, effort)
else:
    print(model, effort)
PY
}

# model_flags [ --provider <name> ] <archetype_id> -> "--model <model>"
model_flags() {
  local out; out="$(model_resolve "$@")" || return $?
  printf -- '--model %s\n' "${out%% *}"
}

# CLI-Entry (nur wenn direkt ausgefuehrt, nicht beim source)
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  _mode=resolve
  _full=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --provider) BOBNET_PROVIDER="$2"; shift 2 ;;
      --full) _full=1; shift ;;
      --model) _mode=flags; shift ;;
      "") shift ;;
      -*) echo "usage: model.sh [--provider claude|devin|codex|cursor] [--model] [--full] <archetype_id>" >&2; exit 2 ;;
      *) break ;;
    esac
  done
  id="${1:-}"
  [ -n "$id" ] || { echo "usage: model.sh [--provider claude|devin|codex|cursor] [--model] [--full] <archetype_id>" >&2; exit 2; }
  if [ "$_mode" = "flags" ]; then
    model_flags --provider "$BOBNET_PROVIDER" "$id"
  else
    model_resolve --provider "$BOBNET_PROVIDER" $( [ "$_full" = 1 ] && echo --full ) "$id"
  fi
fi
