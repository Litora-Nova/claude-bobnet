#!/usr/bin/env bash
# scut-reminder.sh <tag> <message> [level] — SCUT-Ping an Austin + entfernt danach
# die eigene crontab-Zeile (Einmal-Reminder; Zeile endet auf "# <tag>").
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; ROOT="$(cd "$DIR/../.." && pwd)"
tag="$1"; msg="$2"; lvl="${3:-mid}"
"$ROOT/standup/scut.sh" "$msg" "$lvl" >/dev/null 2>&1
crontab -l 2>/dev/null | grep -v "# ${tag}\$" | crontab - 2>/dev/null
echo "reminder $tag gefeuert + Zeile entfernt"
