#!/usr/bin/env bash
# channels/bridge.sh — SCUT-Channel-Adapter: BobNet-Bridge (cross-server) → normalisiertes Event.
#
# Empfängerseite der Brücke zwischen zwei Bobiverse-Installationen (Issue #14/#45): liest
# Klartext-Zeilen von STDIN (EINE Nachricht pro Zeile) und emittiert pro Zeile EIN
# normalisiertes Event (TSV, 6 Felder — siehe scut-router.sh). Pipe in den Router:
#
#     ... | scripts/channels/bridge.sh | scripts/scut-router.sh
#
# Vorgesehen als FORCED-COMMAND-Ziel eines dedizierten Bridge-SSH-Keys (authorized_keys:
# `command="…/bridge.sh | …/scut-router.sh" restrict`): der Peer kann damit AUSSCHLIESSLICH
# Nachrichten inbox-first zustellen — keine Shell, kein anderer Zugriff. Die Gegenseite
# braucht keine Engine: `printf '%s\n' "[acme]@Bob: hallo" | ssh -i bridgekey user@host`
# reicht (agent-agnostisch — auch Nicht-Claude-Bobiverses können senden).
#
# Target-Extraktion wie telegram/email (Triage-Vorstufe; Router entscheidet final):
#   führendes "[<uid>]" und/oder "@<Agent>" → target; nichts davon → ungerichtet → Review-Queue.
#
# Env:
#   BRIDGE_PEER       Absender-Label (Default "peer"; Host-Verdrahtung setzt den Peer-Namen)
#   BRIDGE_MAX_LINES  max. Nachrichten pro Verbindung (Default 20 — Flutschutz)
#   BRIDGE_MAX_LEN    max. Zeichen pro Nachricht (Default 2000 — Rest wird abgeschnitten)
#
# --demo : zwei Beispiel-Events (für Router-Smoke-Tests).
set -uo pipefail

if [ "${1:-}" = "--demo" ]; then
  now="$(date +%s)"
  printf 'bridge\t%s-1\t%s\tacme-peer\t[acme]@Bill\tStatus-Update von der anderen Seite\n' "$now" "$now"
  printf 'bridge\t%s-2\t%s\tacme-peer\t\tUngerichtete Notiz ohne Adressaten\n' "$now" "$now"
  exit 0
fi

PEER="${BRIDGE_PEER:-peer}"
MAX_LINES="${BRIDGE_MAX_LINES:-20}"
MAX_LEN="${BRIDGE_MAX_LEN:-2000}"

# emit_event <channel> <ext_id> <ts> <sender> <rawtext>
#   (Variante von channels/email.sh — inkl. Doppelpunkt-Strip nach @Agent, weil Bridge-
#    Nachrichten wie Betreffzeilen "[uid]@Agent: Text" geschrieben werden.)
emit_event() {
  local channel="$1" ext="$2" ts="$3" sender="$4" raw="$5"
  local target="" rest="$raw"
  if printf '%s' "$rest" | grep -qE '^\[[A-Za-z0-9_-]+\]'; then
    local uidpart; uidpart="$(printf '%s' "$rest" | sed -E 's/^(\[[A-Za-z0-9_-]+\]).*/\1/')"
    target="$uidpart"; rest="$(printf '%s' "$rest" | sed -E 's/^\[[A-Za-z0-9_-]+\][[:space:]]*//')"
  fi
  if printf '%s' "$rest" | grep -qE '^@[A-Za-z0-9_-]+'; then
    local ag; ag="$(printf '%s' "$rest" | sed -E 's/^(@[A-Za-z0-9_-]+).*/\1/')"
    target="${target}${ag}"; rest="$(printf '%s' "$rest" | sed -E 's/^@[A-Za-z0-9_-]+[[:space:]:]*//')"
  fi
  printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$channel" "$ext" "$ts" "$sender" "$target" "$rest"
}

n=0
now="$(date +%s)"
while IFS= read -r line || [ -n "$line" ]; do
  # Sanitize: Tabs zu Spaces (TSV-Integrität), auf MAX_LEN kappen, Leerzeilen überspringen.
  line="$(printf '%.'"$MAX_LEN"'s' "$line" | tr '\t' ' ')"
  [ -z "${line// /}" ] && continue
  n=$((n+1))
  [ "$n" -gt "$MAX_LINES" ] && { echo "bridge-channel: MAX_LINES=$MAX_LINES erreicht — Rest verworfen" >&2; break; }
  emit_event "bridge" "$now-$n" "$now" "$PEER" "$line"
done
exit 0
