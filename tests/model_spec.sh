#!/usr/bin/env bash
# tests/model_spec.sh — scripts/lib/model.sh (Model+Effort-Resolver, Issue #36).
# Fixture-basiert (race-frei, unabhaengig von den echten archetypes/).
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB="$HERE/../scripts/lib/model.sh"
pass=0; fail=0
t(){ local d="$1" exp="$2" got="$3"; if [ "$got" = "$exp" ]; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL: $d — erwartet '$exp', bekam '$got'"; fi; }

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
printf '{"id":"gen","modelTier":"HEAVEN","model":"opus","effort":"xhigh"}' > "$tmp/gen.json"
printf '{"id":"probe","modelTier":"Probe","model":"haiku"}'               > "$tmp/probe.json"  # effort -> Fallback low
printf '{"id":"bare","modelTier":"Cruiser"}'                              > "$tmp/bare.json"   # model+effort -> Fallback sonnet/medium
printf '{"id":"adv","modelTier":"HEAVEN","model":"fable","effort":"xhigh"}' > "$tmp/adv.json"   # fable = Mythos-Class (advisor)

t "explizit"        "opus xhigh"     "$(BOBNET_ARCHETYPES=$tmp bash "$LIB" gen)"
t "effort-fallback" "haiku low"      "$(BOBNET_ARCHETYPES=$tmp bash "$LIB" probe)"
t "tier-fallback"   "sonnet medium"  "$(BOBNET_ARCHETYPES=$tmp bash "$LIB" bare)"
t "fable-explizit"  "fable xhigh"    "$(BOBNET_ARCHETYPES=$tmp bash "$LIB" adv)"
t "--model-flag"    "--model opus"   "$(BOBNET_ARCHETYPES=$tmp bash "$LIB" --model gen)"
t "env-override"    "sonnet high"    "$(BOBNET_ARCHETYPES=$tmp BOBNET_MODEL_OVERRIDE=sonnet BOBNET_EFFORT_OVERRIDE=high bash "$LIB" gen)"
BOBNET_ARCHETYPES=$tmp bash "$LIB" nope >/dev/null 2>&1; t "missing-rc3" "3" "$?"

echo "model_spec: $pass passed, $fail failed"
[ "$fail" = 0 ]
