#!/usr/bin/env bash
# Heartbeat-Logger fürs BobNet-Dashboard (universell, claude-bobnet).
#
# Usage:  log.sh <Agent> <status> <message...>
#   status: busy | idle | blocked | done
#
# Hängt "YYYY-MM-DD HH:MM | status | message" an <STANDUP_DIR>/<Agent>.log an.
# Eine Datei pro Agent => keine Schreibkonflikte im gemeinsamen Working Tree.
# Format mit Datum (sort-stabil); Parser akzeptiert auch altes "HH:MM | …".
#
# Env:
#   STANDUP_DIR   Zielordner der Logs (Default: Verzeichnis dieses Scripts)
#   DEV_TEAM_TZ   Zeitzone (Default: Europe/Berlin)
set -euo pipefail

DIR="${STANDUP_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
agent="${1:?Agent fehlt}"
status="${2:?status fehlt (busy|idle|blocked|done)}"
shift 2
msg="$*"
ts="$(TZ="${DEV_TEAM_TZ:-Europe/Berlin}" date '+%Y-%m-%d %H:%M')"

mkdir -p "$DIR"
printf '%s | %s | %s\n' "$ts" "$status" "$msg" >> "${DIR}/${agent}.log"
