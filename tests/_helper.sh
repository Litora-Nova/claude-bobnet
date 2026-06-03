#!/usr/bin/env bash
# tests/_helper.sh — minimales Black-Box-Test-Harness für die Engine-Shell-Scripts.
#
# Warum eigenes Harness statt der `--self-test`-Modi der Scripts: ein im selben Script
# eingebauter Self-Test driftet mit dem Code mit (self-confirming). Diese Specs leben
# UNABHÄNGIG unter tests/, rufen die Scripts als Black-Box auf und asserten gegen das
# in team-rules/commits.md + scut-router.sh-Header beschriebene SPEC-Verhalten.
#
# Konventionen:
#   - Jede Spec ist ausführbar (`bash tests/<name>.sh`) und liefert Exit 0 = GRÜN, 1 = ROT.
#   - tests/run.sh führt alle tests/*_spec.sh aus und aggregiert.
#   - ALLE Fixtures in mktemp -d; NIE in echte Registry/standup/theme schreiben.
#
# API:
#   it "<beschreibung>"                          # registriert + zählt einen Check (vor ok/eq/…)
#   ok        <cmd…>            : cmd rc==0
#   not_ok    <cmd…>            : cmd rc!=0
#   eq        <got> <want>      : String-Gleichheit
#   neq       <got> <want>      : String-Ungleichheit
#   contains  <haystack> <needle>
#   not_contains <haystack> <needle>
#   file_has  <file> <substr>  : grep -qF im File
#   file_missing <file>        : File existiert NICHT (oder leer)
#   summary                    : druckt Bilanz, setzt globalen Exit-Code

set -uo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENGINE_ROOT_DEFAULT="$(cd "$TESTS_DIR/.." && pwd)"
ENGINE_ROOT="${ENGINE_ROOT:-$ENGINE_ROOT_DEFAULT}"
SCRIPTS="$ENGINE_ROOT/scripts"

_T_PASS=0
_T_FAIL=0
_T_DESC="(unnamed)"

it()   { _T_DESC="$1"; }

_pass() { _T_PASS=$((_T_PASS+1)); printf '  ✓ %s\n' "$_T_DESC"; }
_fail() { _T_FAIL=$((_T_FAIL+1)); printf '  ✗ %s\n' "$_T_DESC"; [ -n "${1:-}" ] && printf '      %s\n' "$1"; }

ok()     { if "$@" >/dev/null 2>&1; then _pass; else _fail "cmd rc!=0: $*"; fi; }
not_ok() { if "$@" >/dev/null 2>&1; then _fail "cmd unexpectedly rc==0: $*"; else _pass; fi; }

eq()  { if [ "$1" = "$2" ]; then _pass; else _fail "got:  [$1]
      want: [$2]"; fi; }
neq() { if [ "$1" != "$2" ]; then _pass; else _fail "both were: [$1]"; fi; }

contains()     { case "$1" in *"$2"*) _pass;; *) _fail "haystack lacks [$2]:
      [$1]";; esac; }
not_contains() { case "$1" in *"$2"*) _fail "haystack unexpectedly has [$2]:
      [$1]";; *) _pass;; esac; }

file_has()     { if grep -qF -- "$2" "$1" 2>/dev/null; then _pass; else _fail "file [$1] lacks [$2]"; fi; }
file_missing() { if [ ! -s "$1" ]; then _pass; else _fail "file [$1] exists/non-empty but should not"; fi; }

summary() {
  local total=$((_T_PASS+_T_FAIL))
  printf '── %d checks: %d ✓ / %d ✗\n' "$total" "$_T_PASS" "$_T_FAIL"
  [ "$_T_FAIL" = 0 ]
}
