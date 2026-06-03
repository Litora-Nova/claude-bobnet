#!/usr/bin/env bash
# scut-morning.sh <tag> <ping|recheck> [level] — Morgen-Ping an den Menschen +
# Erinnerung wenn keine Antwort kommt. Einmal-Reminder-Muster (jede crontab-Zeile
# entfernt sich nach dem Feuern selbst — Zeile endet auf "# <tag>").
#
#   ping    : sendet den Morgen-Ping, merkt sich den aktuellen Telegram-Offset als
#             Antwort-Baseline (<secrets>/morning_ping_offset), entfernt die eigene
#             crontab-Zeile (# <tag>).
#   recheck : vergleicht aktuellen Offset mit Baseline.
#             - Offset gewachsen   -> Antwort eingegangen -> ALLE morn-*-Zeilen raus.
#             - Offset unverändert  -> keine Antwort -> Re-Ping (eskaliert), eigene Zeile raus.
#
# Antwort-Erkennung nutzt <secrets>/telegram_offset (scut-poll.sh erhöht ihn NUR bei
# neuer eingehender Nachricht) — kein Text-Parsing nötig.
#
# Env:
#   SCUT_SECRETS_DIR  telegram_offset / morning_ping_offset (Default: <root>/.secrets)
#   STANDUP_DIR       Ordner mit scut.sh (Default: <root>/standup)
#   SCUT_MORNING_PING   Override für den Morgen-Ping-Text (Default: generischer Text)
#   SCUT_MORNING_REMIND Override für den Reminder-Text (Default: generischer Text)
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$DIR/../.." && pwd)"
SECRETS="${SCUT_SECRETS_DIR:-$ROOT/.secrets}"
SDIR="${STANDUP_DIR:-$ROOT/standup}"
OFFSET_FILE="$SECRETS/telegram_offset"
BASE_FILE="$SECRETS/morning_ping_offset"
SCUT="$SDIR/scut.sh"

tag="${1:?Usage: scut-morning.sh <tag> <ping|recheck> [level]}"
phase="${2:-ping}"
lvl="${3:-mid}"

PING="${SCUT_MORNING_PING:-Guten Morgen! Hier ist der vereinbarte Morgen-Ping. Melde dich kurz, wenn du wach bist.}"
REMIND="${SCUT_MORNING_REMIND:-Reminder: noch keine Antwort von dir — alles ok? Sonst lass ich dich in Ruhe.}"

cur_offset() { cat "$OFFSET_FILE" 2>/dev/null || echo 0; }
rm_self()    { crontab -l 2>/dev/null | grep -v "# ${tag}\$" | crontab - 2>/dev/null; }

case "$phase" in
  ping)
    cur_offset > "$BASE_FILE"
    "$SCUT" "$PING" "$lvl" >/dev/null 2>&1
    rm_self
    echo "scut-morning: ping gefeuert (baseline offset $(cat "$BASE_FILE" 2>/dev/null))"
    ;;
  recheck)
    base="$(cat "$BASE_FILE" 2>/dev/null || echo 0)"
    now="$(cur_offset)"
    if [ "${now:-0}" -gt "${base:-0}" ]; then
      crontab -l 2>/dev/null | grep -v "# morn-" | crontab - 2>/dev/null   # alle Morgen-Reminder raus
      rm -f "$BASE_FILE"
      echo "scut-morning: Antwort eingegangen (offset $base -> $now) -> alle Reminder entfernt"
    else
      "$SCUT" "$REMIND" "$lvl" >/dev/null 2>&1
      rm_self
      echo "scut-morning: keine Antwort (offset $now) -> Reminder gefeuert + Zeile $tag entfernt"
    fi
    ;;
  *) echo "scut-morning: unbekannte phase '$phase'"; exit 1 ;;
esac
