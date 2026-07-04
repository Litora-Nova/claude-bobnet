#!/usr/bin/env bash
# tests/exec_mode_spec.sh — Hygiene: alle Scripts sind im GIT-INDEX ausführbar (100755).
# Hintergrund (Fleet-Finding 2026-07-04): ein Script ritt mit 100644 nach main → systemd-
# Direkt-Exec schlug fehl. Der Working-Tree-Mode täuscht; verbindlich ist der Index-Mode.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
pass=0; fail=0

while IFS=$'\t' read -r meta path; do
  case "$(basename "$path")" in .*) continue;; esac   # Platzhalter wie .gitkeep sind keine Scripts
  mode="${meta%% *}"
  if [ "$mode" = "100755" ]; then pass=$((pass+1))
  else fail=$((fail+1)); echo "FAIL: $path ist $mode (erwartet 100755) — Fix: git update-index --chmod=+x $path"; fi
done < <(git -C "$ROOT" ls-files -s -- 'scripts/*.sh' 'scripts/channels/*.sh' 'scripts/cron/*.sh' 'scripts/lib/*.sh' 'tests/*.sh' 'bin/*' 'hooks/*.sh' 2>/dev/null)

[ $((pass+fail)) -gt 0 ] || { echo "FAIL: keine Dateien gefunden (Pfad-Globs kaputt?)"; fail=1; }
echo "exec_mode_spec: $pass passed, $fail failed"
[ "$fail" = 0 ]
