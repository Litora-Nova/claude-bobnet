#!/usr/bin/env bash
# bobnet-send.sh — Senderseite der BobNet-Bridge: Nachricht an ein Peer-Bobiverse (Issue #14/#45).
#
#   bobnet-send.sh <peer> "<nachricht>"
#
# <nachricht> im Kanal-Kanon: optional führendes "[<uid>]" und/oder "@<Agent>" adressiert;
# ohne Adressierung landet sie drüben in der Review-Queue. Beispiel:
#   bobnet-send.sh codex "[acme]@Bob: Release 0.7.0 ist auf main"
#
# Transport: EINE Zeile auf stdin einer SSH-Verbindung — die Gegenseite hängt einen
# forced-command-Key davor (bridge.sh | scut-router.sh), d.h. dieser Client hat KEINE
# Shell drüben und muss den Remote-Pfad nicht kennen. Kein Secret verlässt diese Seite.
#
# Peers-Auflösung (erste Quelle gewinnt; Daten vor Code, nichts hartkodiert):
#   1. $BOBNET_PEERS                    (Pfad zu einer peers.json)
#   2. Key "peers" in ~/.claude/bobiverse.json  (Pfad zu einer peers.json)
#   3. ~/.claude/bobiverse-peers.json   (Default)
#
# peers.json-Format:
#   { "peers": [ { "name": "codex", "host": "<tailscale-ip-oder-name>",
#                  "user": "<ssh-user>", "key": "~/.ssh/bobnet_bridge" } ] }
#
# Env:
#   BRIDGE_TRANSPORT_CMD  Override des Transports (Kommando, bekommt die Zeile auf stdin;
#                         Platzhalter {host} {user} {key} werden ersetzt) — für Tests/Alternativen.
# Exit: 0 gesendet · 1 Transportfehler · 2 Fehlbedienung/Peer unbekannt.
set -uo pipefail

peer="${1:-}"; shift || true
msg="${*:-}"
[ -n "$peer" ] && [ -n "$msg" ] || { echo "usage: bobnet-send.sh <peer> \"<nachricht>\"" >&2; exit 2; }

# Peers-File auflösen (analog news.sh-Pfadauflösung).
peers_file="${BOBNET_PEERS:-}"
if [ -z "$peers_file" ] && [ -f "$HOME/.claude/bobiverse.json" ]; then
  peers_file="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("peers",""))' "$HOME/.claude/bobiverse.json" 2>/dev/null)"
fi
peers_file="${peers_file:-$HOME/.claude/bobiverse-peers.json}"
case "$peers_file" in "~"/*) peers_file="$HOME/${peers_file#\~/}";; esac
[ -f "$peers_file" ] || { echo "bobnet-send: keine peers.json ($peers_file) — Peer '$peer' nicht auflösbar" >&2; exit 2; }

# Peer-Eintrag lesen → "host<TAB>user<TAB>key" (leer wenn unbekannt).
entry="$(PEERS_FILE="$peers_file" PEER="$peer" python3 - <<'PY'
import json, os, sys
try:
    with open(os.environ["PEERS_FILE"]) as fh:
        data = json.load(fh)
except Exception:
    sys.exit(0)
for p in data.get("peers", []):
    if isinstance(p, dict) and p.get("name") == os.environ["PEER"]:
        print("%s\t%s\t%s" % (p.get("host",""), p.get("user",""), p.get("key","")))
        break
PY
)"
host="$(printf '%s' "$entry" | cut -f1)"
user_="$(printf '%s' "$entry" | cut -f2)"
key="$(printf '%s' "$entry" | cut -f3)"
[ -n "$host" ] || { echo "bobnet-send: Peer '$peer' nicht in $peers_file" >&2; exit 2; }
case "$key" in "~"/*) key="$HOME/${key#\~/}";; esac

# EINE Zeile, Tabs/Newlines geplättet (TSV-/Kanon-Integrität wie news.sh).
line="$(printf '%s' "$msg" | tr '\n\t' '  ')"

if [ -n "${BRIDGE_TRANSPORT_CMD:-}" ]; then
  cmd="${BRIDGE_TRANSPORT_CMD//\{host\}/$host}"
  cmd="${cmd//\{user\}/$user_}"
  cmd="${cmd//\{key\}/$key}"
  printf '%s\n' "$line" | bash -c "$cmd" || { echo "bobnet-send: Transport fehlgeschlagen (override)" >&2; exit 1; }
else
  keyopt=(); [ -n "$key" ] && keyopt=(-i "$key")
  printf '%s\n' "$line" | ssh "${keyopt[@]}" -o BatchMode=yes -o ConnectTimeout=6 \
    "${user_:+$user_@}$host" 2>/dev/null \
    || { echo "bobnet-send: SSH-Zustellung an $peer ($host) fehlgeschlagen" >&2; exit 1; }
fi
echo "✓ bridge → $peer: $line"
