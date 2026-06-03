#!/usr/bin/env bash
# tests/run.sh — Test-Gate: führt alle tests/*_spec.sh aus und aggregiert das Ergebnis.
#
# Exit 0 = GRÜN (alle Specs bestanden) · Exit 1 = ROT (mind. eine Spec fehlgeschlagen).
# Nutzung:   bash tests/run.sh            # alle Specs
#            bash tests/run.sh git_identity_spec.sh scut_router_spec.sh   # gezielt
#
# Jede Spec ist self-contained (eigene mktemp-Fixtures, eigenes summary → Exit-Code).
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ "$#" -gt 0 ]; then
  specs=("$@")
else
  # Feste, geordnete Default-Reihenfolge (1) git-identity (2) scut-router (3) archetypes.
  # Danach jede weitere *_spec.sh automatisch anhängen, falls sie hier (noch) nicht gelistet ist
  # — so fährt das Gate neue Specs mit, ohne dass die bekannte Reihenfolge driftet.
  specs=(git_identity_spec.sh scut_router_spec.sh archetypes_spec.sh)
  for f in "$HERE"/*_spec.sh; do
    [ -e "$f" ] || continue
    b="$(basename "$f")"
    listed=0
    for s in "${specs[@]}"; do [ "$s" = "$b" ] && listed=1 && break; done
    [ "$listed" = 0 ] && specs+=("$b")
  done
fi

green=0; red=0; failed=()
for s in "${specs[@]}"; do
  printf '\n=== %s ===\n' "$s"
  if bash "$HERE/$s"; then green=$((green+1)); else red=$((red+1)); failed+=("$s"); fi
done

printf '\n════════════════════════════════════════\n'
printf 'TEST-GATE: %d Spec(s) GRÜN, %d ROT\n' "$green" "$red"
if [ "$red" -gt 0 ]; then
  printf 'ROT: %s\n' "${failed[*]}"
  printf '════════════════════════════════════════\n'
  exit 1
fi
printf 'GATE GRÜN ✓\n'
printf '════════════════════════════════════════\n'
