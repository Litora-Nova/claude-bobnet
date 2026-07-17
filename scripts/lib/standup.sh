#!/usr/bin/env bash
# scripts/lib/standup.sh — geteilte Lead-Zustands-Helper (Anti-Lärm-Batch, Welle 1).
#
# Extrahiert aus scripts/inbox-watch.sh + bin/recycle: beide lasen Lead-Heartbeat-Logs und lösten
# `~` in Registry-Pfaden byte-identisch gleich auf (Riker-bestätigtes Duplikat, 0.15.0-Review).
# NUR die tatsächlich identisch-dupliziert gewesenen Helper wandern hierher. Die env-Reader
# (`env_of` in inbox-watch.sh — sed-Parsing, einfache Werte; `env_get` in bin/recycle —
# Subshell-Source für $VAR-Expansion in BOOT_CMD) bleiben BEWUSST getrennt: unterschiedliche
# Kontrakte (siehe Kommentar in bin/recycle), ein Merge wäre eine Verhaltensänderung ohne Not.
#
# Kontrakt: von `set -uo pipefail`-Callern gesourct, keine Nebenwirkungen beim Sourcen selbst.
set -uo pipefail

# expand_tilde <pfad> — Registry speichert `~` ggf. literal; hier auf $HOME expandieren.
expand_tilde() { case "$1" in "~"/*) printf '%s' "$HOME/${1#\~/}";; *) printf '%s' "$1";; esac; }

# lead_state <log> — "idle|done|busy|blocked|none:age_min" aus der letzten Heartbeat-Zeile.
lead_state() {
  local log="$1"
  [ -f "$log" ] || { printf 'none:0'; return; }
  local last; last="$(tail -n1 "$log")"
  local ts st
  ts="$(printf '%s' "$last" | cut -d'|' -f1 | sed 's/[[:space:]]*$//')"
  st="$(printf '%s' "$last" | cut -d'|' -f2 | tr -d ' ')"
  # Unparsbarer Timestamp → als STALE behandeln (age=99999): ein kaputter Heartbeat darf einen
  # Nudge/ein Recycle-Gate nicht ewig unterdrücken (busy-frisch wäre die falsche Default-Annahme).
  local es now age=99999
  es="$(date -d "$ts" +%s 2>/dev/null || echo 0)"; now="$(date +%s)"
  [ "$es" -gt 0 ] && age=$(( (now-es)/60 ))
  printf '%s:%s' "${st:-none}" "$age"
}

# log_line_count <log> -> Zeilenzahl (0 wenn Datei fehlt).
log_line_count() { [ -f "$1" ] && wc -l < "$1" | tr -d ' ' || printf '0'; }

# heartbeat_since <log> <lines_at_snapshot> -> true wenn seither eine NEUE Zeile angehängt wurde.
heartbeat_since() { [ "$(log_line_count "$1")" -gt "$2" ]; }
