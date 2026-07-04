#!/usr/bin/env bash
# scripts/news.sh — zentrale News-Box des Bobiverse (EIN File pro Installation).
#
# Für Updates, die ALLE Teams betreffen: Engine-Releases, neue geteilte Tools/MCP-Server
# (+ wo das How-to liegt), geänderte Konventionen. KEIN Ersatz für die Projekt-Inbox
# (Agent-zu-Agent innerhalb eines Teams, siehe comms.md) — die News-Box ist Broadcast:
# one-line, append-only, dauerhaft greppbar. Jeder Bob liest sie beim Stand-up
# (routines.md); jeder Lead darf posten. Kanon: team-rules/news.md.
#
#   news.sh post "<text>"   Eintrag anhängen (Datum + Absender automatisch)
#   news.sh read [N]        letzte N Einträge zeigen (Default 10)
#   news.sh path            aufgelösten News-File-Pfad ausgeben
#
# Auflösung des News-Files (erste Quelle gewinnt):
#   1. $BOBNET_NEWS
#   2. Key "news" in ~/.claude/bobiverse.json
#   3. ~/.claude/bobiverse-news.md (Default)
# Absender: $NEWS_FROM > $PROJECT_UID > $TEAM_LEAD > $USER
# jq-frei (python3), konsistent mit scripts/lib/model.sh.
set -uo pipefail

resolve_news() {
  if [ -n "${BOBNET_NEWS:-}" ]; then printf '%s' "$BOBNET_NEWS"; return; fi
  local cfg="$HOME/.claude/bobiverse.json" p=""
  [ -f "$cfg" ] && p="$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1])).get("news",""))' "$cfg" 2>/dev/null)"
  printf '%s' "${p:-$HOME/.claude/bobiverse-news.md}"
}

FILE="$(resolve_news)"
FROM="${NEWS_FROM:-${PROJECT_UID:-${TEAM_LEAD:-${USER:-bob}}}}"
TZc="${DEV_TEAM_TZ:-Europe/Berlin}"

case "${1:-}" in
  post)
    shift; text="${*:-}"
    [ -n "$text" ] || { echo "usage: news.sh post \"<text>\"" >&2; exit 2; }
    text="$(printf '%s' "$text" | tr '\n' ' ')"   # Kanon: EINE Zeile pro Eintrag
    mkdir -p "$(dirname "$FILE")"
    printf '%s | @all | %s | %s\n' "$(TZ="$TZc" date '+%Y-%m-%d %H:%M')" "$FROM" "$text" >> "$FILE"
    echo "✓ news → $FILE"
    ;;
  read)
    n="${2:-10}"
    case "$n" in *[!0-9]*|"") echo "usage: news.sh read [N] — N muss eine Zahl sein (bekam '$n')" >&2; exit 2;; esac
    [ -f "$FILE" ] || { echo "(News-Box leer — $FILE existiert noch nicht)"; exit 0; }
    tail -n "$n" "$FILE"
    ;;
  path) printf '%s\n' "$FILE" ;;
  *) echo "usage: news.sh post \"<text>\" | news.sh read [N] | news.sh path" >&2; exit 2 ;;
esac
