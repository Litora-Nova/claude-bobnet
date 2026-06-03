#!/usr/bin/env bash
# scut.sh — Team-Lead -> Mensch (Telegram). KURZE Pings/Antworten.
# Usage: scut.sh "<nachricht>" [info|mid|urgent]
#
# Env:
#   SCUT_SECRETS_DIR  Ordner mit telegram_token + telegram_chat_id
#                     (Default: <repo-root-über-scripts>/.secrets)
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SECRETS="${SCUT_SECRETS_DIR:-$(cd "$DIR/.." && pwd)/.secrets}"
TOKEN="$(cat "$SECRETS/telegram_token" 2>/dev/null)"
CHAT="$(cat "$SECRETS/telegram_chat_id" 2>/dev/null)"
{ [ -z "$TOKEN" ] || [ -z "$CHAT" ]; } && { echo "scut: kein token/chat in $SECRETS" >&2; exit 1; }
MSG="${1:?Usage: scut.sh \"<nachricht>\" [info|mid|urgent]}"
LEVEL="${2:-info}"
case "$LEVEL" in urgent) P="🔴";; mid) P="🟡";; *) P="🟢";; esac
MSG="$(printf '%s' "$MSG" | cut -c1-900)"   # soft-cap
curl -s --max-time 12 "https://api.telegram.org/bot${TOKEN}/sendMessage" \
  --data-urlencode "chat_id=${CHAT}" --data-urlencode "text=${P} ${MSG}" \
  -o /dev/null -w "scut HTTP %{http_code}\n"
