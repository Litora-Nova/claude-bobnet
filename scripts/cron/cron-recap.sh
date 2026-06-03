#!/usr/bin/env bash
# Tagesabschluss-Recap (cron): fasst Commits/Sprint via claude -p zusammen + SCUT-Ping.
# Env: STANDUP_DIR, TEAM_LEAD, LEAD_PERSONA (Rollen-Beschreibung), LEAD_SIGNOFF (Gute-Nacht-Text).
set -uo pipefail
export NVM_DIR="$HOME/.nvm"; [ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh" >/dev/null 2>&1
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; ROOT="$(cd "$DIR/../.." && pwd)"; ST="${STANDUP_DIR:-$ROOT/standup}"
LEAD="${TEAM_LEAD:-Bob}"; PERSONA="${LEAD_PERSONA:-Tech-Lead}"; SIGNOFF="${LEAD_SIGNOFF:-Gute Nacht.}"
d="$(date +%F)"
DATA="$( { echo "Commits heute:"; git -C "$ROOT" log --all --since="$d 00:00" --pretty='- %h %an: %s' 2>/dev/null | head -40; echo; echo "Sprint-Stand:"; sed -n '1,40p' "$ST/_sprint.md" 2>/dev/null; } )"
REP="$(printf '%s\n' "$DATA" | claude -p "Du bist $LEAD, $PERSONA. Schreibe einen knappen Tagesabschluss-Report (Deutsch, Markdown): Was lief/shipped heute, was bleibt offen, 1-2 Saetze ehrliches Self-Feedback. Kompakt, keine Vorrede." </dev/null 2>/dev/null)"
[ -z "$REP" ] && REP="$DATA"
{ echo "# Tagesabschluss $d"; echo; printf '%s\n' "$REP"; } > "$ST/report-$d.md"
"$ST/scut.sh" "Tagesabschluss $d geschrieben (report-$d.md). $SIGNOFF" info >/dev/null 2>&1
echo "[recap] ok $d"
