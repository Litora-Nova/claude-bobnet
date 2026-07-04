#!/usr/bin/env bash
# bridge-receive.sh <peer> — Empfänger der BobNet-Bridge (forced command, Issue #45).
#
# Läuft als FORCED COMMAND eines dedizierten Bridge-SSH-Keys (eine authorized_keys-Zeile
# pro Peer/Richtung, mit `restrict` + `from=` gepinnt — Layout: Host-Trust-Doc der Instanz).
# Der Peer-Name kommt als ARGUMENT aus der authorized_keys-Zeile (authentische Identität,
# nie vom Client); die Nachricht kommt als DATEN aus SSH_ORIGINAL_COMMAND (Fallback stdin)
# und wird NIEMALS ausgeführt.
#
# Sicherheits-Kontrakt (Serverwächter-Design 2026-07-04):
#   - max 4 KB, GENAU eine Zeile, Control-Chars werden gestrippt (Tab → Space)
#   - Pflicht-Adressierung: führendes `[<uid>]` oder `[<uid>]@<Agent>`
#     (Regex ^\[[a-z0-9_-]{1,32}\](@[A-Za-z0-9_-]{1,32})?$) — sonst REJECT
#   - Ziel-Inbox löst der EMPFÄNGER aus der Registry auf (Client kann keinen Pfad wählen);
#     [uid] ohne Agent → TEAM_LEAD des Projekts (dev-team.env, Default Bob)
#   - Kanon-Zeile wird SERVERSEITIG gestempelt: `<ts> | @<Agent> | BRIDGE (<peer>): <text>`
#     (+ Signatur `— (<lead>@<peer>)`, wenn peers.json den Peer-Lead kennt); Append mit flock
#   - Audit-PFLICHT: jede Annahme/Ablehnung → $BRIDGE_LOG (ts · accept/reject+Grund · peer ·
#     target · bytes · Auszug)
#   - Exit 0 = zugestellt · 2 = REJECT (Sender darf NICHT blind retryn)
#
# Env:
#   DEV_TEAM_REGISTRY  zentrale projects.registry.json (Default wie scut-router.sh)
#   BOBNET_PEERS       peers.json (Default-Auflösung wie bobnet-send.sh) — nur für Peer-Lead-Signatur
#   BRIDGE_LOG         Audit-Log (Default $HOME/standup/bridge.log, sonst $HOME/.claude/bobiverse-bridge.log)
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENGINE_ROOT="${ENGINE_ROOT:-$(cd "$DIR/.." && pwd)}"
TOOLHUB="$(cd "$ENGINE_ROOT/.." && pwd)"
REGISTRY="${DEV_TEAM_REGISTRY:-$TOOLHUB/projects.registry.json}"

PEER="${1:-}"
if [ -n "${BRIDGE_LOG:-}" ]; then LOG="$BRIDGE_LOG"
elif [ -d "$HOME/standup" ]; then LOG="$HOME/standup/bridge.log"
else LOG="$HOME/.claude/bobiverse-bridge.log"; fi

audit() { # audit <ACCEPT|REJECT grund> <target> <bytes> <auszug>
  mkdir -p "$(dirname "$LOG")" 2>/dev/null
  printf '%s | %s | peer=%s | target=%s | %sB | %s\n' \
    "$(date '+%Y-%m-%d %H:%M:%S')" "$1" "${PEER:-?}" "${2:-—}" "${3:-0}" "${4:-}" >> "$LOG" 2>/dev/null || true
}
reject() { audit "REJECT: $1" "${2:-—}" "${3:-0}" "${4:-}"; echo "bridge-receive: REJECT — $1" >&2; exit 2; }

[ -n "$PEER" ] || reject "kein Peer-Argument (authorized_keys-Zeile prüfen)"

# ── Input: SSH_ORIGINAL_COMMAND als Daten, Fallback stdin; max 4 KB ─────────────────────────
raw="${SSH_ORIGINAL_COMMAND:-}"
[ -z "$raw" ] && raw="$(head -c 5000 2>/dev/null || true)"
bytes="${#raw}"
[ "$bytes" -gt 0 ] || reject "leere Nachricht" "—" 0
[ "$bytes" -le 4096 ] || reject "über 4KB (${bytes}B)" "—" "$bytes"
raw="${raw%$'\n'}"                                   # EIN trailing newline (stdin) ist ok
case "$raw" in *$'\n'*) reject "mehr als eine Zeile" "—" "$bytes";; esac
text="$(printf '%s' "$raw" | tr '\t' ' ' | tr -d '\000-\010\013\014\016-\037\177')"
[ -n "${text// /}" ] || reject "leer nach Sanitize" "—" "$bytes"

# ── Pflicht-Target extrahieren + validieren ─────────────────────────────────────────────────
tgt="$(printf '%s' "$text" | grep -oE '^\[[a-z0-9_-]{1,32}\](@[A-Za-z0-9_-]{1,32})?' | head -n1)"
[ -n "$tgt" ] || reject "kein/ungültiges Target (Pflicht: [uid] oder [uid]@Agent)" "—" "$bytes" "${text:0:60}"
rest="${text#"$tgt"}"; rest="${rest#:}"; rest="${rest## }"; rest="${rest%% }"
rest="$(printf '%s' "$rest" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')"
[ -n "$rest" ] || reject "leerer Text nach Target" "$tgt" "$bytes"
uid="${tgt#[}"; uid="${uid%%]*}"
agent="${tgt#*]}"; agent="${agent#@}"

# ── Ziel-Inbox löst der Empfänger auf (Registry; kein Client-Pfad, kein Traversal) ──────────
expand_tilde() { case "$1" in "~"/*) printf '%s' "$HOME/${1#\~/}";; *) printf '%s' "$1";; esac; }
reg_lookup() {
  REG_FILE="$REGISTRY" REG_UID="$1" REG_FIELD="$2" python3 - <<'PY'
import json, os, sys
try:
    with open(os.environ["REG_FILE"]) as fh:
        data = json.load(fh)
except Exception:
    sys.exit(0)
for p in data.get("projects", []):
    if isinstance(p, dict) and p.get("uid") == os.environ["REG_UID"]:
        sys.stdout.write(str(p.get(os.environ["REG_FIELD"], "")))
        break
PY
}
standup="$(expand_tilde "$(reg_lookup "$uid" standup)")"
[ -n "$standup" ] || reject "unbekannte uid '$uid' (nicht in Registry)" "$tgt" "$bytes"
inbox="$standup/_inbox.md"

if [ -z "$agent" ]; then
  proj="$(expand_tilde "$(reg_lookup "$uid" path)")"
  envf="$proj/_dev_team/dev-team.env"
  [ -f "$envf" ] && agent="$(sed -n 's/^export TEAM_LEAD="\{0,1\}\([^"]*\)"\{0,1\}.*/\1/p' "$envf" | head -n1)"
  agent="${agent:-Bob}"
fi

# ── Peer-Lead-Signatur (optional, aus peers.json des Empfängers) ────────────────────────────
peers_file="${BOBNET_PEERS:-}"
if [ -z "$peers_file" ] && [ -f "$HOME/.claude/bobiverse.json" ]; then
  peers_file="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("peers",""))' "$HOME/.claude/bobiverse.json" 2>/dev/null)"
fi
peers_file="${peers_file:-$HOME/.claude/bobiverse-peers.json}"
peers_file="$(expand_tilde "$peers_file")"
lead=""
[ -f "$peers_file" ] && lead="$(PEERS_FILE="$peers_file" PEER_NAME="$PEER" python3 - <<'PY'
import json, os
try:
    with open(os.environ["PEERS_FILE"]) as fh:
        data = json.load(fh)
    entry = data.get(os.environ["PEER_NAME"]) or {}
    print(entry.get("lead", "") if isinstance(entry, dict) else "")
except Exception:
    pass
PY
)"

# ── Serverseitig stempeln + flock-Append ────────────────────────────────────────────────────
line="$(date '+%Y-%m-%d %H:%M') | @$agent | BRIDGE ($PEER): $rest"
[ -n "$lead" ] && line="$line — ($lead@$PEER)"
mkdir -p "$(dirname "$inbox")"
{ flock -x 9; printf '%s\n' "$line" >&9; } 9>>"$inbox" \
  || reject "Append fehlgeschlagen ($inbox)" "$tgt" "$bytes"

audit "ACCEPT" "$tgt" "$bytes" "${rest:0:60}"
echo "✓ bridge-receive: [$uid]@$agent ← $PEER (${bytes}B)"
exit 0
