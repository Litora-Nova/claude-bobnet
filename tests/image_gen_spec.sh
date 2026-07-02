#!/usr/bin/env bash
# tests/image_gen_spec.sh — scripts/image-gen.sh (Arg-/Cred-Handling, OHNE Netzwerk).
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SH="$HERE/../scripts/image-gen.sh"
pass=0; fail=0
t(){ local d="$1" exp="$2" got="$3"; if [ "$got" = "$exp" ]; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL: $d — erwartet '$exp', bekam '$got'"; fi; }

( bash "$SH" --help >/dev/null 2>&1 ); t "help-rc2"  "2" "$?"
( bash "$SH"        >/dev/null 2>&1 ); t "empty-rc2" "2" "$?"
( BOBNET_SECRETS=/nonexistent-xyz bash "$SH" "prompt" >/dev/null 2>&1 ); t "missing-dir-rc3" "3" "$?"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
( BOBNET_SECRETS="$tmp" bash "$SH" "prompt" >/dev/null 2>&1 ); t "missing-creds-rc3" "3" "$?"

echo "image_gen_spec: $pass passed, $fail failed"
[ "$fail" = 0 ]
