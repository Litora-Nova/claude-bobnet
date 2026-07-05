#!/usr/bin/env bash
# bobnet-send.sh — Senderseite der BobNet-Bridge: Nachricht an ein Peer-Bobiverse (Issue #45).
#
#   bobnet-send.sh <peer> "[<uid>][@<Agent>]: <text>"
#
# PFLICHT-Adressierung mit führendem `[<uid>]` (optional `@<Agent>`) — der Empfänger-Kontrakt
# (bridge-receive.sh) REJECTet alles andere; wir validieren lokal vor, um Netz zu sparen.
#
# Transport: die Zeile geht als SSH-Kommando-String raus und landet drüben als
# SSH_ORIGINAL_COMMAND — reine DATEN für die forced command (bridge-receive.sh <peer>),
# die dort in der authorized_keys-Zeile verdrahtet ist. Dieser Client hat drüben KEINE
# Shell und kennt keine Remote-Pfade; Zeitstempel + Absender-Identität stempelt der
# Empfänger selbst (kein Spoofing). Kein Secret verlässt diese Seite.
#
# Transport-Sicherheit (Issue #49, Codex-Review H1): die Nachricht geht IMMER auf STDIN,
# NIE als SSH-Kommando-String. So kann sie drüben nicht in der Kommando-Position landen und
# — bei fehlkonfiguriertem/fehlendem forced-command — als Shell-Input ausgeführt werden.
# Damit stdin sicher ist, MUSS die Gegenseite den Text als Daten (nicht als Login-Shell)
# empfangen. Der Peer deklariert das in peers.json, sonst verweigert der Sender (fail hard):
#   "forced": true   der Empfänger ist ein forced-command-Key, der stdin liest → kein Kommando.
#   "recv": "<cmd>"  explizites Remote-Empfangskommando (TRUSTED config) → stdin geht dort rein.
# Fehlt beides → EXIT 2 (wir würden sonst an eine Login-Shell pipen = unsicher).
#
# peers.json (Map; Daten vor Code, Auflösung wie news.sh):
#   { "codex-2": { "host": "<tailscale-ip-oder-name>", "user": "<ssh-user>",
#                  "key": "~/.ssh/bridge/bridge_<peer>", "lead": "<peer-lead>",
#                  "forced": true } }   // ODER "recv": "<remote-empfangskommando>"
#   1. $BOBNET_PEERS  2. Key "peers" in ~/.claude/bobiverse.json  3. ~/.claude/bobiverse-peers.json
#
# Env:
#   BRIDGE_TRANSPORT_CMD  Transport-Override NUR für Tests (bekommt die Zeile auf stdin;
#                         Platzhalter {host} {user} {key} werden ersetzt). Umgeht den
#                         forced/recv-Guard bewusst — nicht mit untrusted peers.json nutzen.
# Exit: 0 zugestellt · 1 Transportfehler · 2 Fehlbedienung / Peer unbekannt/unsicher / REJECT.
set -uo pipefail

peer="${1:-}"; shift || true
msg="${*:-}"
[ -n "$peer" ] && [ -n "$msg" ] || { echo "usage: bobnet-send.sh <peer> \"[<uid>][@<Agent>]: <text>\"" >&2; exit 2; }

# EINE Zeile, Tabs/Newlines geplättet (Empfänger nimmt genau eine Zeile an).
line="$(printf '%s' "$msg" | tr '\n\t' '  ')"

# Lokale Vor-Validierung gegen den Empfänger-Kontrakt (spart den Netz-Roundtrip).
if ! printf '%s' "$line" | grep -qE '^\[[a-z0-9_-]{1,32}\](@[A-Za-z0-9_-]{1,32})?([: ]|$)'; then
  echo "bobnet-send: Nachricht braucht führendes [<uid>] oder [<uid>]@<Agent> (Empfänger-Kontrakt)" >&2
  exit 2
fi

# peers.json auflösen.
peers_file="${BOBNET_PEERS:-}"
if [ -z "$peers_file" ] && [ -f "$HOME/.claude/bobiverse.json" ]; then
  peers_file="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("peers",""))' "$HOME/.claude/bobiverse.json" 2>/dev/null)"
fi
peers_file="${peers_file:-$HOME/.claude/bobiverse-peers.json}"
case "$peers_file" in "~"/*) peers_file="$HOME/${peers_file#\~/}";; esac
[ -f "$peers_file" ] || { echo "bobnet-send: keine peers.json ($peers_file) — Peer '$peer' nicht auflösbar" >&2; exit 2; }

entry="$(PEERS_FILE="$peers_file" PEER="$peer" python3 - <<'PY'
import json, os, sys
try:
    with open(os.environ["PEERS_FILE"]) as fh:
        data = json.load(fh)
except Exception:
    sys.exit(0)
entry = data.get(os.environ["PEER"])
if isinstance(entry, dict):
    forced = "1" if entry.get("forced") is True else ""
    print("%s\t%s\t%s\t%s\t%s" % (entry.get("host",""), entry.get("user",""),
                                   entry.get("key",""), forced, entry.get("recv","")))
PY
)"
host="$(printf '%s' "$entry" | cut -f1)"
user_="$(printf '%s' "$entry" | cut -f2)"
key="$(printf '%s' "$entry" | cut -f3)"
forced="$(printf '%s' "$entry" | cut -f4)"
recv="$(printf '%s' "$entry" | cut -f5)"
[ -n "$host" ] || { echo "bobnet-send: Peer '$peer' nicht in $peers_file" >&2; exit 2; }
case "$key" in "~"/*) key="$HOME/${key#\~/}";; esac

if [ -n "${BRIDGE_TRANSPORT_CMD:-}" ]; then
  cmd="${BRIDGE_TRANSPORT_CMD//\{host\}/$host}"
  cmd="${cmd//\{user\}/$user_}"
  cmd="${cmd//\{key\}/$key}"
  printf '%s\n' "$line" | bash -c "$cmd"
  rc=$?
else
  # H1: Payload NIE als Kommando. Sicher nur, wenn die Gegenseite ihn als Daten empfängt:
  #   recv gesetzt → explizites Empfangskommando (trusted config); sonst forced-command-Key.
  # Ohne beides würden wir an eine Login-Shell pipen → verweigern.
  if [ -z "$recv" ] && [ "$forced" != 1 ]; then
    echo "bobnet-send: Peer '$peer' ist weder \"forced\":true noch hat \"recv\" — Senden verweigert (Payload dürfte NICHT in eine Login-Shell; siehe #49)." >&2
    exit 2
  fi
  keyopt=(); [ -n "$key" ] && keyopt=(-i "$key")
  # recv (unsere Config, kein User-Text) in Kommando-Position; die NACHRICHT geht auf stdin.
  printf '%s\n' "$line" | ssh "${keyopt[@]}" -o BatchMode=yes -o ConnectTimeout=6 \
    "${user_:+$user_@}$host" ${recv:+"$recv"} >/dev/null 2>&1
  rc=$?
  [ "$rc" -eq 255 ] && { echo "bobnet-send: SSH-Transport zu $peer ($host) fehlgeschlagen" >&2; exit 1; }
fi
if [ "$rc" -ne 0 ]; then
  echo "bobnet-send: Gegenseite hat abgelehnt/Fehler (rc=$rc) — nicht blind retryn" >&2
  exit 2
fi
echo "✓ bridge → $peer: $line"
