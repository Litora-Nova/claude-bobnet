#!/usr/bin/env bash
# tests/spawn_spec.sh — scripts/lib/spawn.sh (Provider-Spawn-Command-Builder).
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB="$HERE/../scripts/lib/spawn.sh"
pass=0; fail=0

t(){ local d="$1" exp="$2" got="$3"; if [ "$got" = "$exp" ]; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL: $d — erwartet '$exp', bekam '$got'"; fi; }

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
printf '{"id":"backend","modelTier":"HEAVEN","model":"opus","effort":"xhigh","providers":{"claude":{"model":"sonnet","effort":"xhigh"},"devin":{"model":"swe-1-6","effort":"high"}}}' > "$tmp/backend.json"

t "binary-claude" "claude" "$(BOBNET_ARCHETYPES=$tmp bash "$LIB" --binary claude)"
t "binary-devin"  "devin"  "$(BOBNET_ARCHETYPES=$tmp bash "$LIB" --binary devin)"
t "cmd-claude"    "claude --model sonnet -- bash start.sh" "$(BOBNET_ARCHETYPES=$tmp bash "$LIB" claude backend 'bash start.sh')"
t "cmd-devin"     "devin --model swe-1-6 -- bash start.sh" "$(BOBNET_ARCHETYPES=$tmp bash "$LIB" devin backend 'bash start.sh')"
t "cmd-env"       "devin --model swe-1-6 -- bash start.sh" "$(BOBNET_ARCHETYPES=$tmp BOBNET_PROVIDER=devin bash "$LIB" backend 'bash start.sh')"
t "binary-unknown" "2" "$(BOBNET_ARCHETYPES=$tmp bash "$LIB" --binary openai >/dev/null 2>&1; echo $?)"

echo "spawn_spec: $pass passed, $fail failed"
[ "$fail" = 0 ]
