#!/usr/bin/env bash
# tests/bridge_spec.sh — BobNet-Bridge (#45): bridge-receive.sh (forced command) + bobnet-send.sh.
# Kontrakt-Quelle: Trust-Design der Host-Seite (max 4KB · 1 Zeile · Pflicht-Target-Regex ·
# Empfänger stempelt/löst Pfade selbst · Audit-Pflicht · exit 0/2).
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RECV="$HERE/../scripts/bridge-receive.sh"
SEND="$HERE/../scripts/bobnet-send.sh"
pass=0; fail=0
t(){ local d="$1" exp="$2" got="$3"; if [ "$got" = "$exp" ]; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL: $d — erwartet '$exp', bekam '$got'"; fi; }
ok(){ local d="$1"; shift; if "$@" >/dev/null 2>&1; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL: $d"; fi; }

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
ok "bash -n bridge-receive.sh" bash -n "$RECV"
ok "bash -n bobnet-send.sh" bash -n "$SEND"

# ── Fixtures: Registry (Projekt alpha, Lead Zed) + peers.json (codex-2, Lead Rob) ───────────
mkdir -p "$tmp/alpha/_dev_team/standup" "$tmp/beta/_dev_team/standup" "$tmp/locked/standup"
cat > "$tmp/registry.json" <<JSON
{ "version":1, "projects":[
  {"uid":"alpha","name":"alpha","path":"$tmp/alpha","standup":"$tmp/alpha/_dev_team/standup","status":"active"},
  {"uid":"beta","name":"beta","path":"$tmp/beta","standup":"$tmp/beta/_dev_team/standup","status":"active"},
  {"uid":"locked","name":"locked","path":"$tmp/locked","standup":"$tmp/locked/standup","status":"active"}
]}
JSON
printf 'export TEAM_LEAD="Zed"\n' > "$tmp/alpha/_dev_team/dev-team.env"
cat > "$tmp/peers.json" <<JSON
{ "codex-2":   { "host": "203.0.113.7", "user": "acme", "key": "$tmp/fakekey", "lead": "Rob", "forced": true },
  "recvpeer":  { "host": "203.0.113.9", "user": "acme", "key": "$tmp/fakekey", "recv": "~/bobnet/recv.sh" },
  "unsafepeer":{ "host": "203.0.113.8" },
  "plainpeer": { "host": "203.0.113.8" } }
JSON
INBOX="$tmp/alpha/_dev_team/standup/_inbox.md"
LOG="$tmp/bridge.log"
recv(){ DEV_TEAM_REGISTRY="$tmp/registry.json" BOBNET_PEERS="$tmp/peers.json" BRIDGE_LOG="$LOG" bash "$RECV" "$@"; }

# ── Empfänger: ACCEPT-Pfade ─────────────────────────────────────────────────────────────────
t "accept [uid]@Agent via SSH_ORIGINAL_COMMAND: exit 0" "0" \
  "$(SSH_ORIGINAL_COMMAND='[alpha]@Bill: hallo drüben' recv codex-2 >/dev/null 2>&1; echo $?)"
t "Kanon-Zeile serverseitig gestempelt + Peer-Lead-Signatur" "1" \
  "$(grep -cE '^[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2} \| @Bill \| BRIDGE \(codex-2\): hallo drüben — \(Rob@codex-2\)$' "$INBOX")"
SSH_ORIGINAL_COMMAND='[alpha] nur ans Projekt' recv codex-2 >/dev/null 2>&1
t "[uid] ohne Agent → TEAM_LEAD aus dev-team.env" "1" "$(grep -c '| @Zed | BRIDGE (codex-2): nur ans Projekt' "$INBOX")"
printf '[alpha]@Bill: über stdin\n' | recv codex-2 >/dev/null 2>&1
t "stdin-Fallback (ohne SSH_ORIGINAL_COMMAND)" "1" "$(grep -c 'über stdin' "$INBOX")"
SSH_ORIGINAL_COMMAND="$(printf '[alpha]@Bill: mit\007klingel und\ttab')" recv codex-2 >/dev/null 2>&1
t "Control-Chars gestrippt, Tab → Space" "1" "$(grep -c 'mitklingel und tab' "$INBOX")"

# ── Empfänger: REJECT-Pfade (alle exit 2 + Audit) ───────────────────────────────────────────
t "ohne Target → REJECT 2" "2" "$(SSH_ORIGINAL_COMMAND='hallo ohne adresse' recv codex-2 >/dev/null 2>&1; echo $?)"
t "Großschreibung in uid → REJECT 2 (Regex lowercase)" "2" "$(SSH_ORIGINAL_COMMAND='[Alpha]@Bill: hi' recv codex-2 >/dev/null 2>&1; echo $?)"
t "unbekannte uid → REJECT 2" "2" "$(SSH_ORIGINAL_COMMAND='[ghost]@Bill: hi' recv codex-2 >/dev/null 2>&1; echo $?)"
t "leerer Text nach Target → REJECT 2" "2" "$(SSH_ORIGINAL_COMMAND='[alpha]@Bill:' recv codex-2 >/dev/null 2>&1; echo $?)"
t "mehr als eine Zeile → REJECT 2" "2" "$(printf '[alpha]@Bill: a\nzweite\n' | recv codex-2 >/dev/null 2>&1; echo $?)"
t "über 4KB → REJECT 2" "2" "$(SSH_ORIGINAL_COMMAND="[alpha]@Bill: $(printf 'x%.0s' $(seq 1 4200))" recv codex-2 >/dev/null 2>&1; echo $?)"
t "ohne Peer-Argument → REJECT 2" "2" "$(SSH_ORIGINAL_COMMAND='[alpha]@Bill: hi' recv >/dev/null 2>&1; echo $?)"

# Audit-Pflicht: ACCEPTs + REJECTs geloggt, Peer ausgewiesen
t "Audit: ACCEPTs geloggt" "4" "$(grep -c '| ACCEPT |' "$LOG")"
ok "Audit: REJECTs geloggt mit Grund" grep -q 'REJECT: kein/ungültiges Target' "$LOG"
ok "Audit: Peer ausgewiesen" grep -q 'peer=codex-2' "$LOG"

# ── Reject-Blätter + Stempel-Varianten (Review-M1 + Test-Gate-Backlog) ──────────────────────
SSH_ORIGINAL_COMMAND="$(printf '[alpha]@Bill: vor\rnach dem CR')" recv codex-2 >/dev/null 2>&1
t "CR (0x0D) wird gestrippt (Review-M1)" "1" "$(grep -c 'vornach dem CR' "$INBOX")"
t "leere Nachricht (kein SOC, stdin leer) → REJECT 2" "2" "$(recv codex-2 < /dev/null >/dev/null 2>&1; echo $?)"
t "nur Control-Chars → REJECT 2 (leer nach Sanitize)" "2" \
  "$(SSH_ORIGINAL_COMMAND="$(printf '\001\002\003')" recv codex-2 >/dev/null 2>&1; echo $?)"
t "Traversal-uid [../etc] → REJECT 2 (explizit)" "2" \
  "$(SSH_ORIGINAL_COMMAND='[../etc]@x: boese' recv codex-2 >/dev/null 2>&1; echo $?)"
SSH_ORIGINAL_COMMAND='[beta] ohne env-file' recv codex-2 >/dev/null 2>&1
t "uid ohne dev-team.env → Agent-Default Bob" "1" "$(grep -c '| @Bob | BRIDGE (codex-2): ohne env-file' "$tmp/beta/_dev_team/standup/_inbox.md")"
SSH_ORIGINAL_COMMAND='[alpha]@Bill: vom plainpeer' recv plainpeer >/dev/null 2>&1
t "Peer ohne lead → Zeile OHNE Signatur" "1" "$(grep -cE 'BRIDGE \(plainpeer\): vom plainpeer$' "$INBOX")"
touch "$tmp/locked/standup/_inbox.md"; chmod 444 "$tmp/locked/standup/_inbox.md"
t "unschreibbare Inbox → REJECT 2 (Append fehlgeschlagen)" "2" \
  "$(SSH_ORIGINAL_COMMAND='[locked]@x: hi' recv codex-2 >/dev/null 2>&1; echo $?)"
chmod 644 "$tmp/locked/standup/_inbox.md"
ok "Audit: Append-Fehlschlag geloggt" grep -q 'REJECT: Append fehlgeschlagen' "$LOG"

# ── Sender: Vor-Validierung + Auflösung ─────────────────────────────────────────────────────
t "send: ohne [uid]-Adressierung → exit 2 (lokal, vor Netz)" "2" \
  "$(BOBNET_PEERS="$tmp/peers.json" bash "$SEND" codex-2 "hallo ohne adresse" >/dev/null 2>&1; echo $?)"
t "send: unbekannter Peer → exit 2" "2" \
  "$(BOBNET_PEERS="$tmp/peers.json" bash "$SEND" niemand "[alpha] hi" >/dev/null 2>&1; echo $?)"
t "send: fehlende peers.json → exit 2" "2" \
  "$(BOBNET_PEERS="$tmp/nix.json" bash "$SEND" codex-2 "[alpha] hi" >/dev/null 2>&1; echo $?)"
t "send: usage → exit 2" "2" "$(bash "$SEND" codex-2 2>/dev/null; echo $?)"

# Transport-Override: Zeile (geplättet) auf stdin, Platzhalter ersetzt
BOBNET_PEERS="$tmp/peers.json" BRIDGE_TRANSPORT_CMD="cat > $tmp/sent-{user}.txt" \
  bash "$SEND" codex-2 "$(printf '[alpha]@Bill: zeile1\nzeile2')" >/dev/null
t "send: Override bekommt geplättete Zeile" "[alpha]@Bill: zeile1 zeile2" "$(tr -d '\n' < "$tmp/sent-acme.txt")"
t "send: Remote-REJECT (rc 2) propagiert als 2" "2" \
  "$(BOBNET_PEERS="$tmp/peers.json" BRIDGE_TRANSPORT_CMD="exit 2" bash "$SEND" codex-2 "[alpha] hi" >/dev/null 2>&1; echo $?)"

# ── ssh-Shim (PATH-Fake): exakte argv + STDIN + Fehlerzweige des ECHTEN ssh-Pfads ───────────
mkdir -p "$tmp/bin"
cat > "$tmp/bin/ssh" <<SH
#!/usr/bin/env bash
printf '%s\n' "\$@" > "$tmp/ssh-argv.txt"
cat > "$tmp/ssh-stdin.txt"
exit "\${FAKE_SSH_RC:-0}"
SH
chmod +x "$tmp/bin/ssh"

# H1 (#49): forced-Peer → Payload auf STDIN, KEIN Kommando in argv
PATH="$tmp/bin:$PATH" BOBNET_PEERS="$tmp/peers.json" bash "$SEND" codex-2 "[alpha]@Bill: echt per ssh" >/dev/null
ok "ssh-argv: -i <key>" grep -qx -- "$tmp/fakekey" "$tmp/ssh-argv.txt"
ok "ssh-argv: BatchMode=yes" grep -qx -- "BatchMode=yes" "$tmp/ssh-argv.txt"
ok "ssh-argv: user@host" grep -qx -- "acme@203.0.113.7" "$tmp/ssh-argv.txt"
t "H1: forced → letztes argv ist user@host, NICHT die Nachricht" "acme@203.0.113.7" "$(tail -1 "$tmp/ssh-argv.txt")"
t "H1: Nachricht steht NICHT in argv" "0" "$(grep -c 'echt per ssh' "$tmp/ssh-argv.txt")"
t "H1: Nachricht kommt über STDIN an" "[alpha]@Bill: echt per ssh" "$(tr -d '\n' < "$tmp/ssh-stdin.txt")"

# H1: recv-Peer → recv-Kommando (unsere Config) IN argv, Payload weiter auf stdin
PATH="$tmp/bin:$PATH" BOBNET_PEERS="$tmp/peers.json" bash "$SEND" recvpeer "[alpha]@Bill: via recv" >/dev/null
t "H1: recv-Kommando in argv (letztes Arg)" "~/bobnet/recv.sh" "$(tail -1 "$tmp/ssh-argv.txt")"
t "H1: Payload NICHT in recv-argv" "0" "$(grep -c 'via recv' "$tmp/ssh-argv.txt")"
t "H1: recv-Payload über stdin" "[alpha]@Bill: via recv" "$(tr -d '\n' < "$tmp/ssh-stdin.txt")"

# H1 Fail-Hard: Peer ohne forced UND ohne recv → verweigern (kein Senden an eine Login-Shell)
t "H1 Fail-Hard: weder forced noch recv → exit 2" "2" \
  "$(PATH="$tmp/bin:$PATH" BOBNET_PEERS="$tmp/peers.json" bash "$SEND" unsafepeer "[alpha] hi" >/dev/null 2>&1; echo $?)"
rm -f "$tmp/ssh-argv.txt"
PATH="$tmp/bin:$PATH" BOBNET_PEERS="$tmp/peers.json" bash "$SEND" unsafepeer "[alpha] hi" >/dev/null 2>&1
ok "H1 Fail-Hard: ssh gar nicht aufgerufen (keine argv-Datei)" test ! -e "$tmp/ssh-argv.txt"

t "ssh rc=255 → Transportfehler exit 1" "1" \
  "$(PATH="$tmp/bin:$PATH" FAKE_SSH_RC=255 BOBNET_PEERS="$tmp/peers.json" bash "$SEND" codex-2 "[alpha] hi" >/dev/null 2>&1; echo $?)"
t "ssh rc=2 (Remote-REJECT) → exit 2" "2" \
  "$(PATH="$tmp/bin:$PATH" FAKE_SSH_RC=2 BOBNET_PEERS="$tmp/peers.json" bash "$SEND" codex-2 "[alpha] hi" >/dev/null 2>&1; echo $?)"

# ── Roundtrip ohne SSH: Sender-Override pipet in den Empfänger (stdin-Fallback) ─────────────
BOBNET_PEERS="$tmp/peers.json" BRIDGE_TRANSPORT_CMD="DEV_TEAM_REGISTRY=$tmp/registry.json BOBNET_PEERS=$tmp/peers.json BRIDGE_LOG=$LOG bash $RECV codex-2" \
  bash "$SEND" codex-2 "[alpha]@Bill: roundtrip komplett" >/dev/null
t "Roundtrip: Zeile landet in der Ziel-Inbox" "1" "$(grep -c 'BRIDGE (codex-2): roundtrip komplett' "$INBOX")"

echo "bridge_spec: $pass passed, $fail failed"
[ "$fail" = 0 ]
