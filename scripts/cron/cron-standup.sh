#!/usr/bin/env bash
# Morgen-Standup (cron): fasst Commits/Heartbeats/Offen via claude -p zusammen + SCUT-Ping.
# Env: STANDUP_DIR, TEAM_LEAD, LEAD_PERSONA (Rollen-Beschreibung), QA_ASKED_BY (Empfänger).
set -uo pipefail
export NVM_DIR="$HOME/.nvm"; [ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh" >/dev/null 2>&1
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; ROOT="$(cd "$DIR/../.." && pwd)"; ST="${STANDUP_DIR:-$ROOT/standup}"
LEAD="${TEAM_LEAD:-Bob}"; PERSONA="${LEAD_PERSONA:-Tech-Lead}"; HUMAN="${QA_ASKED_BY:-Owner}"
ts="$(date '+%Y-%m-%d %H:%M')"
DATA="$( { echo "Commits 24h:"; git -C "$ROOT" log --all --since='24 hours ago' --pretty='- %h %an: %s' 2>/dev/null | head -20; echo; echo "Heartbeats:"; for f in "$ST"/*.log; do b="$(basename "$f" .log)"; [ "$b" = releases ] && continue; echo "- $b: $(tail -1 "$f" 2>/dev/null | cut -c1-80)"; done; echo; echo "Offen:"; sed -n '/Offen/,/Production/p' "$ST/_sprint.md" 2>/dev/null | head -12; echo; echo "Bug-Check zuletzt:"; tail -6 "$ST/_bugs.md" 2>/dev/null; } )"
SUM="$(printf '%s\n' "$DATA" | claude -p "Du bist $LEAD, $PERSONA. Mach daraus einen KURZEN Morgen-Standup fuer $HUMAN (Deutsch, ~6 Zeilen, handytauglich): wichtigste Bewegungen, offene Tasks, ob etwas rot ist. Keine Vorrede, kein Titel." </dev/null 2>/dev/null)"
[ -z "$SUM" ] && SUM="$DATA"
{ echo "# Morgen-Standup $ts"; echo; printf '%s\n' "$SUM"; } > "$ST/report-standup-$(date +%F).md"
"$ST/scut.sh" "Morgen-Standup $ts
$SUM" info >/dev/null 2>&1
echo "[standup] ok $ts"
