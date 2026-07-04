#!/usr/bin/env bash
# tests/bridge_spec.sh — BobNet-Bridge: channels/bridge.sh (Empfänger) + bobnet-send.sh (Sender).
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BRIDGE="$HERE/../scripts/channels/bridge.sh"
SEND="$HERE/../scripts/bobnet-send.sh"
ROUTER="$HERE/../scripts/scut-router.sh"
pass=0; fail=0
t(){ local d="$1" exp="$2" got="$3"; if [ "$got" = "$exp" ]; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL: $d — erwartet '$exp', bekam '$got'"; fi; }
ok(){ local d="$1"; shift; if "$@" >/dev/null 2>&1; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL: $d"; fi; }

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
ok "bash -n bridge.sh" bash -n "$BRIDGE"
ok "bash -n bobnet-send.sh" bash -n "$SEND"

# ── Empfänger: stdin-Zeilen → normalisierte Events ────────────────────────────────────────
t "--demo: 2 Events, channel=bridge" "2" "$(bash "$BRIDGE" --demo | grep -c '^bridge	')"

out="$(printf '%s\n' "[acme]@Bill: bitte Review" | BRIDGE_PEER=codex bash "$BRIDGE")"
t "gerichtet: target aus [uid]@Agent" "[acme]@Bill" "$(printf '%s\n' "$out" | cut -f5)"
t "gerichtet: Doppelpunkt gestrippt" "bitte Review" "$(printf '%s\n' "$out" | cut -f6)"
t "sender = BRIDGE_PEER" "codex" "$(printf '%s\n' "$out" | cut -f4)"

t "ungerichtet: target leer" "" "$(printf 'nur eine notiz\n' | bash "$BRIDGE" | cut -f5)"
t "Leerzeilen übersprungen" "1" "$(printf '\n\nhallo\n\n' | bash "$BRIDGE" | wc -l | tr -d ' ')"
t "Tab im Text → Space (TSV-Integrität, 6 Felder)" "6" "$(printf 'a\tb\n' | bash "$BRIDGE" | awk -F'\t' '{print NF}')"
t "MAX_LINES kappt Flut" "2" "$(printf '1\n2\n3\n4\n' | BRIDGE_MAX_LINES=2 bash "$BRIDGE" 2>/dev/null | wc -l | tr -d ' ')"
t "MAX_LEN kappt Zeile" "5" "$(printf 'abcdefgh\n' | BRIDGE_MAX_LEN=5 bash "$BRIDGE" | cut -f6 | tr -d '\n' | wc -c | tr -d ' ')"

# Ende-zu-Ende: bridge → router (Dry-Run) triagiert gerichtet + ungerichtet
route="$(printf '%s\n%s\n' "[acme]@Bill: hi" "lose Notiz" | BRIDGE_PEER=codex bash "$BRIDGE" \
  | SCUT_ROUTER_DRYRUN=1 DEV_TEAM_REGISTRY="$tmp/keine.json" CONTEXT_UID=ctx bash "$ROUTER" 2>/dev/null)"
t "Router-Smoke: gerichtet → inbox[acme]" "1" "$(printf '%s\n' "$route" | grep -c 'inbox\[acme\]')"
t "Router-Smoke: ungerichtet → review-queue" "1" "$(printf '%s\n' "$route" | grep -c 'review-queue\[ctx\]')"

# ── Sender: peers-Auflösung + Transport-Override ──────────────────────────────────────────
cat > "$tmp/peers.json" <<JSON
{ "peers": [ { "name": "codex", "host": "203.0.113.7", "user": "acme", "key": "~/.ssh/nope" } ] }
JSON

t "send: unbekannter Peer → exit 2" "2" \
  "$(BOBNET_PEERS="$tmp/peers.json" bash "$SEND" niemand "hi" >/dev/null 2>&1; echo $?)"
t "send: ohne Nachricht → usage exit 2" "2" "$(bash "$SEND" codex 2>/dev/null; echo $?)"
t "send: fehlende peers.json → exit 2" "2" \
  "$(BOBNET_PEERS="$tmp/gibtsnicht.json" bash "$SEND" codex "hi" >/dev/null 2>&1; echo $?)"

# Transport-Override: Zeile landet im File, Platzhalter werden ersetzt
BOBNET_PEERS="$tmp/peers.json" BRIDGE_TRANSPORT_CMD="cat > $tmp/sent-{user}.txt" \
  bash "$SEND" codex "[acme]@Bill: über die Brücke" >/dev/null
t "send: Transport bekommt die Zeile" "[acme]@Bill: über die Brücke" "$(cat "$tmp/sent-acme.txt" 2>/dev/null | tr -d '\n')"

# Mehrzeiliges wird geplättet (EINE Zeile über die Brücke)
BOBNET_PEERS="$tmp/peers.json" BRIDGE_TRANSPORT_CMD="cat > $tmp/flat.txt" \
  bash "$SEND" codex "$(printf 'zeile1\nzeile2')" >/dev/null
t "send: Newlines geplättet" "1" "$(wc -l < "$tmp/flat.txt" | tr -d ' ')"

# Sende→Empfangs-Roundtrip ohne SSH: Transport pipet direkt in bridge.sh
BOBNET_PEERS="$tmp/peers.json" BRIDGE_TRANSPORT_CMD="BRIDGE_PEER={user} bash $BRIDGE > $tmp/roundtrip.tsv" \
  bash "$SEND" codex "[acme]@Bill: roundtrip" >/dev/null
t "Roundtrip: Event korrekt (target)" "[acme]@Bill" "$(cut -f5 "$tmp/roundtrip.tsv")"
t "Roundtrip: Event korrekt (sender)" "acme" "$(cut -f4 "$tmp/roundtrip.tsv")"

echo "bridge_spec: $pass passed, $fail failed"
[ "$fail" = 0 ]
