#!/usr/bin/env bash
# SCUT-Empfänger — pollt Telegram (long-poll getUpdates) und routet neue
# Mensch-Nachrichten nach <STANDUP_DIR>/_inbox.md (+ guarded send-keys an die
# tmux-Session des Team-Leads). Läuft als Dauerschleife (z. B. in tmux 'scut').
#
# Media (Foto/Voice/Audio/Dokument/Video/GIF/Video-Note/Sticker) werden via
# getFile heruntergeladen nach <SCUT_INBOX> und als "[Typ -> pfad]" in die Inbox
# notiert (Album-Kollision wird durch -2/-3-Suffix vermieden).
#
# Env:
#   SCUT_SECRETS_DIR  telegram_token/chat_id/offset (Default: <root>/.secrets)
#   STANDUP_DIR       Inbox-Ordner (Default: <root>/standup)
#   SCUT_INBOX        Download-Ziel für Media (Default: <STANDUP_DIR>/../_inbox)
#   SCUT_TMUX_TARGET  tmux-Session des Leads (Default: bob)
#   SCUT_PREFIX       Inject-Prefix in der Lead-Session (Default: [SCUT])
#   TEAM_LEAD         Inbox-@-Empfänger (Default: Bob)
#   DEV_TEAM_TZ       Zeitzone (Default: Europe/Berlin)
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$DIR/.." && pwd)"
SECRETS="${SCUT_SECRETS_DIR:-$ROOT/.secrets}"
SDIR="${STANDUP_DIR:-$ROOT/standup}"
INBOX="$SDIR/_inbox.md"
MEDIA_INBOX="${SCUT_INBOX:-$(cd "$SDIR/.." && pwd)/_inbox}"
TOKEN="$(cat "$SECRETS/telegram_token" 2>/dev/null)"
CHAT="$(cat "$SECRETS/telegram_chat_id" 2>/dev/null)"
OFFSET_FILE="$SECRETS/telegram_offset"
TARGET="${SCUT_TMUX_TARGET:-bob}"
PREFIX="${SCUT_PREFIX:-[SCUT]}"
LEAD="${TEAM_LEAD:-Bob}"
TZc="${DEV_TEAM_TZ:-Europe/Berlin}"
[ -z "$TOKEN" ] && { echo "FEHLER: kein telegram_token in $SECRETS"; exit 1; }
offset="$(cat "$OFFSET_FILE" 2>/dev/null || echo 0)"
echo "SCUT-Empfänger läuft (offset=$offset) -> $INBOX + tmux:$TARGET (media -> $MEDIA_INBOX)"
while true; do
  resp="$(curl -s --max-time 70 "https://api.telegram.org/bot${TOKEN}/getUpdates?timeout=55&offset=${offset}")" || { sleep 3; continue; }
  [ -z "$resp" ] && { sleep 3; continue; }
  parsed="$(printf '%s' "$resp" | TG_TOKEN="$TOKEN" TG_INBOX="$MEDIA_INBOX" python3 -c '
import sys, json, os, urllib.request
TOKEN = os.environ.get("TG_TOKEN", "")
INBOX_DIR = os.environ.get("TG_INBOX", "_inbox")
def grab(file_id, name):
    # getFile + download nach INBOX_DIR, gibt absoluten Pfad zurueck (oder None)
    if not TOKEN or not file_id:
        return None
    try:
        api = "https://api.telegram.org/bot" + TOKEN
        with urllib.request.urlopen(api + "/getFile?file_id=" + file_id, timeout=20) as r:
            fp = json.load(r).get("result", {}).get("file_path")
        if not fp:
            return None
        ext = os.path.splitext(fp)[1] or os.path.splitext(name)[1] or ""
        safe = os.path.basename(name) or ("tg" + ext)
        if not os.path.splitext(safe)[1] and ext:
            safe = safe + ext
        os.makedirs(INBOX_DIR, exist_ok=True)
        dest = os.path.join(INBOX_DIR, safe)
        b, e2 = os.path.splitext(dest); k = 2          # Album-Kollision vermeiden (gleiche
        while os.path.exists(dest):                    # Sekunde -> gleicher Name -> -2, -3, ...
            dest = "%s-%d%s" % (b, k, e2); k += 1
        url = "https://api.telegram.org/file/bot" + TOKEN + "/" + fp
        with urllib.request.urlopen(url, timeout=60) as resp, open(dest, "wb") as out:
            out.write(resp.read())
        return dest
    except Exception:
        return None
try:
    d = json.load(sys.stdin)
except Exception:
    sys.exit(0)
for u in d.get("result", []):
    m = u.get("message") or u.get("edited_message") or {}
    cid = str((m.get("chat") or {}).get("id", ""))
    date = m.get("date", 0)
    cap = m.get("caption")
    if m.get("text"):
        lab = m["text"]
    elif m.get("photo"):
        p = grab(m["photo"][-1]["file_id"], "tg_%s.jpg" % date)
        lab = ("[Bild -> %s]" % p) if p else "[Bild]"
        if cap: lab = cap + " " + lab
    elif m.get("voice"):
        v = m["voice"]; p = grab(v["file_id"], "tg_%s.ogg" % date)
        dur = v.get("duration", 0); mm = "%d:%02d" % (dur // 60, dur % 60)
        lab = "[Voice %s%s]" % (mm, (" -> " + p) if p else "")
    elif m.get("audio"):
        a = m["audio"]; p = grab(a["file_id"], a.get("file_name") or ("tg_%s.mp3" % date))
        lab = "[Audio%s]" % ((" -> " + p) if p else "")
    elif m.get("document"):
        dc = m["document"]; fn = dc.get("file_name") or ("tg_%s" % date)
        p = grab(dc["file_id"], fn)
        lab = "[Dokument %s%s]" % (fn, (" -> " + p) if p else "")
        if cap: lab = cap + " " + lab
    elif m.get("video"):
        p = grab(m["video"]["file_id"], "tg_%s.mp4" % date)
        lab = "[Video%s]" % ((" -> " + p) if p else "")
        if cap: lab = cap + " " + lab
    elif m.get("animation"):
        p = grab(m["animation"]["file_id"], "tg_%s.gif" % date)
        lab = "[GIF%s]" % ((" -> " + p) if p else "")
    elif m.get("video_note"):
        p = grab(m["video_note"]["file_id"], "tg_%s_note.mp4" % date)
        lab = "[Video-Note%s]" % ((" -> " + p) if p else "")
    elif m.get("sticker"):
        lab = "[Sticker %s]" % (m["sticker"].get("emoji") or "")
    elif cap:
        lab = cap
    else:
        lab = "[non-text]"
    lab = " ".join(str(lab).split())
    print("%s\t%s\t%s\t%s" % (u["update_id"], cid, date, lab))
')"
  [ -z "$parsed" ] && continue
  while IFS=$'\t' read -r uid cid mdate txt; do
    [ -z "$uid" ] && continue
    offset=$((uid+1)); echo "$offset" > "$OFFSET_FILE"
    [ "$cid" = "$CHAT" ] || continue
    ts="$(TZ="$TZc" date '+%Y-%m-%d %H:%M')"
    printf '%s | @%s | SCUT (via Telegram): %s\n' "$ts" "$LEAD" "$txt" >> "$INBOX"
    echo "[$ts] inbox <- $txt"
    now="$(date +%s)"; age=$(( now - ${mdate:-0} ))
    if [ "$age" -lt 180 ] && tmux has-session -t "$TARGET" 2>/dev/null; then
      cmd="$(tmux list-panes -t "$TARGET" -F '#{pane_current_command}' 2>/dev/null | head -1)"
      if [ "$cmd" = "node" ] || [ "$cmd" = "claude" ]; then
        tmux send-keys -t "$TARGET" -l -- "$PREFIX $txt"; tmux send-keys -t "$TARGET" Enter
        echo "  -> an $LEAD (tmux:$TARGET) injiziert"
      else
        echo "  ($TARGET im Shell-Modus [$cmd] -> nur Inbox)"
      fi
    fi
  done <<< "$parsed"
done
