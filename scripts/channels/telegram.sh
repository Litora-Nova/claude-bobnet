#!/usr/bin/env bash
# channels/telegram.sh — SCUT-Channel-Adapter: Telegram → normalisiertes Event (FUNKTIONAL).
#
# Pollt Telegram getUpdates (long-poll) und emittiert pro neuer Mensch-Nachricht EINE normalisierte
# Event-Zeile auf stdout (TSV, 6 Felder — siehe scut-router.sh). Pipe in den Router:
#
#     scripts/channels/telegram.sh | scripts/scut-router.sh
#
# Target-Extraktion aus dem Nachrichtentext (Triage-Vorstufe; Router entscheidet final):
#   führendes "[<uid>]" und/oder "@<Agent>"  → target-Feld; der Rest = text.
#   nichts davon  → target leer (= ungerichtet → Review-Queue).
#
# Env (kompatibel zu scut-poll.sh):
#   SCUT_SECRETS_DIR  telegram_token/chat_id/offset (Default: <engine-root>/.secrets)
#   SCUT_TG_ONESHOT   1 = einmal pollen + raus (für Tests/Cron); sonst Dauerschleife.
#   DEV_TEAM_TZ       nur durchgereicht (Router formatiert die Zeit).
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENGINE_ROOT="${ENGINE_ROOT:-$(cd "$DIR/../.." && pwd)}"
SECRETS="${SCUT_SECRETS_DIR:-$ENGINE_ROOT/.secrets}"
TOKEN="$(cat "$SECRETS/telegram_token" 2>/dev/null)"
CHAT="$(cat "$SECRETS/telegram_chat_id" 2>/dev/null)"
OFFSET_FILE="$SECRETS/telegram_offset"
ONESHOT="${SCUT_TG_ONESHOT:-0}"
[ -z "$TOKEN" ] && { echo "telegram-channel: kein telegram_token in $SECRETS" >&2; exit 1; }
offset="$(cat "$OFFSET_FILE" 2>/dev/null || echo 0)"

poll_once() {
  local resp
  resp="$(curl -s --max-time 70 "https://api.telegram.org/bot${TOKEN}/getUpdates?timeout=55&offset=${offset}")" || return 1
  [ -z "$resp" ] && return 0
  # python3: pro Update eine Roh-Zeile "update_id\tcid\tdate\tsender\ttext" (Text whitespace-normalisiert).
  local parsed
  parsed="$(printf '%s' "$resp" | python3 - <<'PY'
import sys, json
try:
    d = json.load(sys.stdin)
except Exception:
    sys.exit(0)
for u in d.get("result", []):
    m = u.get("message") or u.get("edited_message") or {}
    cid = str((m.get("chat") or {}).get("id", ""))
    date = m.get("date", 0)
    frm = m.get("from") or {}
    sender = frm.get("username") or frm.get("first_name") or "telegram"
    txt = m.get("text") or m.get("caption") or "[non-text]"
    txt = " ".join(str(txt).split())
    print("%s\t%s\t%s\t%s\t%s" % (u["update_id"], cid, date, sender, txt))
PY
)"
  [ -z "$parsed" ] && return 0
  while IFS=$'\t' read -r uid cid mdate sender txt; do
    [ -z "$uid" ] && continue
    offset=$((uid+1)); echo "$offset" > "$OFFSET_FILE"
    [ "$cid" = "$CHAT" ] || continue
    emit_event "telegram" "$uid" "$mdate" "$sender" "$txt"
  done <<< "$parsed"
}

# emit_event <channel> <ext_id> <ts> <sender> <rawtext>
#   extrahiert führendes [uid] und/oder @Agent → target; gibt normalisierte TSV-Zeile aus.
emit_event() {
  local channel="$1" ext="$2" ts="$3" sender="$4" raw="$5"
  local target="" rest="$raw"
  # führendes [uid]
  if printf '%s' "$rest" | grep -qE '^\[[A-Za-z0-9_-]+\]'; then
    local uidpart; uidpart="$(printf '%s' "$rest" | sed -E 's/^(\[[A-Za-z0-9_-]+\]).*/\1/')"
    target="$uidpart"; rest="$(printf '%s' "$rest" | sed -E 's/^\[[A-Za-z0-9_-]+\][[:space:]]*//')"
  fi
  # führendes @Agent
  if printf '%s' "$rest" | grep -qE '^@[A-Za-z0-9_-]+'; then
    local ag; ag="$(printf '%s' "$rest" | sed -E 's/^(@[A-Za-z0-9_-]+).*/\1/')"
    target="${target}${ag}"; rest="$(printf '%s' "$rest" | sed -E 's/^@[A-Za-z0-9_-]+[[:space:]]*//')"
  fi
  printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$channel" "$ext" "$ts" "$sender" "$target" "$rest"
}

if [ "$ONESHOT" = 1 ]; then
  poll_once
else
  echo "telegram-channel: polle (offset=$offset) → normalisierte Events auf stdout" >&2
  while true; do poll_once || sleep 3; done
fi
