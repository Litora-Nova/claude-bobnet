#!/usr/bin/env bash
# tests/news_spec.sh — scripts/news.sh (zentrale News-Box, EIN File pro Installation).
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN="$HERE/../scripts/news.sh"
pass=0; fail=0
t(){ local d="$1" exp="$2" got="$3"; if [ "$got" = "$exp" ]; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL: $d — erwartet '$exp', bekam '$got'"; fi; }
ok(){ local d="$1"; shift; if "$@" >/dev/null 2>&1; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL: $d"; fi; }

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
NEWS="$tmp/sub/news.md"

# post: legt File + Elternordner an; Format = Datum | @all | Absender | Text
BOBNET_NEWS="$NEWS" NEWS_FROM="acme-backend" bash "$BIN" post "MCP-Server X live — How-to: share/mcp-x.md" >/dev/null
ok "post legt File an" test -f "$NEWS"
t "post-Format (Datum|@all|Absender|Text)" "1" \
  "$(grep -cE '^[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2} \| @all \| acme-backend \| MCP-Server X live' "$NEWS")"

# Kanon: EINE Zeile pro Eintrag — mehrzeiliger Input wird geplättet
BOBNET_NEWS="$NEWS" NEWS_FROM="acme" bash "$BIN" post "$(printf 'zeile1\nzeile2')" >/dev/null
t "one-line-Kanon (2 Einträge = 2 Zeilen)" "2" "$(wc -l < "$NEWS" | tr -d ' ')"

# read N zeigt die letzten N Einträge
BOBNET_NEWS="$NEWS" NEWS_FROM="acme" bash "$BIN" post "dritter Eintrag" >/dev/null
t "read 2 liefert 2 Zeilen" "2" "$(BOBNET_NEWS="$NEWS" bash "$BIN" read 2 | wc -l | tr -d ' ')"
t "read: neuester Eintrag zuletzt" "1" "$(BOBNET_NEWS="$NEWS" bash "$BIN" read 1 | grep -c 'dritter Eintrag')"

# read auf fehlendes File: kein Fehler (exit 0, Hinweis)
t "read leer: exit 0" "0" "$(BOBNET_NEWS="$tmp/nix.md" bash "$BIN" read >/dev/null 2>&1; echo $?)"

# Auflösung: BOBNET_NEWS > bobiverse.json > Default
t "path: BOBNET_NEWS gewinnt" "$NEWS" "$(BOBNET_NEWS="$NEWS" bash "$BIN" path)"
mkdir -p "$tmp/home/.claude"
printf '{"news":"%s/vianews.md"}' "$tmp" > "$tmp/home/.claude/bobiverse.json"
t "path: bobiverse.json-Key" "$tmp/vianews.md" "$(HOME="$tmp/home" BOBNET_NEWS= bash "$BIN" path)"
mkdir -p "$tmp/home2"
t "path: Default ohne Config" "$tmp/home2/.claude/bobiverse-news.md" "$(HOME="$tmp/home2" BOBNET_NEWS= bash "$BIN" path)"

# Fehlbedienung: exit 2 + usage
t "post ohne Text: exit 2" "2" "$(BOBNET_NEWS="$NEWS" bash "$BIN" post 2>/dev/null; echo $?)"
t "ohne Kommando: exit 2" "2" "$(BOBNET_NEWS="$NEWS" bash "$BIN" 2>/dev/null; echo $?)"
t "read mit nicht-numerischem N: exit 2 statt tail-Crash" "2" "$(BOBNET_NEWS="$NEWS" bash "$BIN" read abc 2>/dev/null; echo $?)"

echo "news_spec: $pass passed, $fail failed"
[ "$fail" = 0 ]
