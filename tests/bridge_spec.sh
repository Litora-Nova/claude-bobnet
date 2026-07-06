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

# ── Fixtures: Registry (Projekt alpha, Lead Zed) + peers.json (peerB, Lead Rob) ───────────
mkdir -p "$tmp/alpha/_dev_team/standup" "$tmp/beta/_dev_team/standup" "$tmp/locked/standup"
cat > "$tmp/registry.json" <<JSON
{ "version":1, "projects":[
  {"uid":"alpha","name":"alpha","path":"$tmp/alpha","standup":"$tmp/alpha/_dev_team/standup","status":"active"},
  {"uid":"beta","name":"beta","path":"$tmp/beta","standup":"$tmp/beta/_dev_team/standup","status":"active"},
  {"uid":"locked","name":"locked","path":"$tmp/locked","standup":"$tmp/locked/standup","status":"active"}
]}
JSON
printf 'export TEAM_LEAD="Zed"\n' > "$tmp/alpha/_dev_team/dev-team.env"
longlead="$(printf 'X%.0s' $(seq 1 100))"
cat > "$tmp/peers.json" <<JSON
{ "peerB":   { "host": "203.0.113.7", "user": "acme", "key": "$tmp/fakekey", "lead": "Rob", "forced": true },
  "recvpeer":  { "host": "203.0.113.9", "user": "acme", "key": "$tmp/fakekey", "recv": "~/bobnet/recv.sh" },
  "unsafepeer":{ "host": "203.0.113.8" },
  "plainpeer": { "host": "203.0.113.8" },
  "spoofpeer": { "host": "203.0.113.10", "lead": "Rob\nFAKE | ACCEPT | peer=ownedyou" },
  "longleadpeer": { "host": "203.0.113.11", "lead": "$longlead" } }
JSON
INBOX="$tmp/alpha/_dev_team/standup/_inbox.md"
LOG="$tmp/bridge.log"
recv(){ DEV_TEAM_REGISTRY="$tmp/registry.json" BOBNET_PEERS="$tmp/peers.json" BRIDGE_LOG="$LOG" bash "$RECV" "$@"; }

# ── Empfänger: ACCEPT-Pfade ─────────────────────────────────────────────────────────────────
t "accept [uid]@Agent via SSH_ORIGINAL_COMMAND: exit 0" "0" \
  "$(SSH_ORIGINAL_COMMAND='[alpha]@Bill: hallo drüben' recv peerB >/dev/null 2>&1; echo $?)"
t "Kanon-Zeile serverseitig gestempelt + Peer-Lead-Signatur" "1" \
  "$(grep -cE '^[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2} \| @Bill \| BRIDGE \(peerB\): hallo drüben — \(Rob@peerB\)$' "$INBOX")"
SSH_ORIGINAL_COMMAND='[alpha] nur ans Projekt' recv peerB >/dev/null 2>&1
t "[uid] ohne Agent → TEAM_LEAD aus dev-team.env" "1" "$(grep -c '| @Zed | BRIDGE (peerB): nur ans Projekt' "$INBOX")"
printf '[alpha]@Bill: über stdin\n' | recv peerB >/dev/null 2>&1
t "stdin-Fallback (ohne SSH_ORIGINAL_COMMAND)" "1" "$(grep -c 'über stdin' "$INBOX")"
SSH_ORIGINAL_COMMAND="$(printf '[alpha]@Bill: mit\007klingel und\ttab')" recv peerB >/dev/null 2>&1
t "Control-Chars gestrippt, Tab → Space" "1" "$(grep -c 'mitklingel und tab' "$INBOX")"

# ── Empfänger: REJECT-Pfade (alle exit 2 + Audit) ───────────────────────────────────────────
t "ohne Target → REJECT 2" "2" "$(SSH_ORIGINAL_COMMAND='hallo ohne adresse' recv peerB >/dev/null 2>&1; echo $?)"
t "Großschreibung in uid → REJECT 2 (Regex lowercase)" "2" "$(SSH_ORIGINAL_COMMAND='[Alpha]@Bill: hi' recv peerB >/dev/null 2>&1; echo $?)"
t "unbekannte uid → REJECT 2" "2" "$(SSH_ORIGINAL_COMMAND='[ghost]@Bill: hi' recv peerB >/dev/null 2>&1; echo $?)"
t "leerer Text nach Target → REJECT 2" "2" "$(SSH_ORIGINAL_COMMAND='[alpha]@Bill:' recv peerB >/dev/null 2>&1; echo $?)"
t "mehr als eine Zeile → REJECT 2" "2" "$(printf '[alpha]@Bill: a\nzweite\n' | recv peerB >/dev/null 2>&1; echo $?)"
t "über 4KB → REJECT 2" "2" "$(SSH_ORIGINAL_COMMAND="[alpha]@Bill: $(printf 'x%.0s' $(seq 1 4200))" recv peerB >/dev/null 2>&1; echo $?)"
t "ohne Peer-Argument → REJECT 2" "2" "$(SSH_ORIGINAL_COMMAND='[alpha]@Bill: hi' recv >/dev/null 2>&1; echo $?)"

# M4/#51: Byte- statt Zeichen-Limit — 2100x "ü" (2 Bytes/Zeichen in UTF-8) bleibt bei der
# Zeichenzählung weit unter 4096 (~2114 Zeichen), sprengt aber in Bytes klar die Grenze
# (~4214B). Die alte ${#raw}-Zählung hätte das faelschlich ACCEPTet.
umlaut_msg="[alpha]@Bill: $(printf 'ü%.0s' $(seq 1 2100))"
t "M4: Multibyte über 4KB (Bytes) trotz <4096 Zeichen → REJECT 2" "2" \
  "$(SSH_ORIGINAL_COMMAND="$umlaut_msg" recv peerB >/dev/null 2>&1; echo $?)"
ok "M4: Audit nennt den korrekten (hohen) Byte-Wert, nicht die Zeichenzahl" \
  grep -qE '\| REJECT: über 4KB \([0-9]{4,}B\)' "$LOG"

# Audit-Pflicht: ACCEPTs + REJECTs geloggt, Peer ausgewiesen
t "Audit: ACCEPTs geloggt" "4" "$(grep -c '| ACCEPT |' "$LOG")"
ok "Audit: REJECTs geloggt mit Grund" grep -q 'REJECT: kein/ungültiges Target' "$LOG"
ok "Audit: Peer ausgewiesen" grep -q 'peer=peerB' "$LOG"

# ── M3/#51: ACCEPT-Audit ist fail-closed (kaputtes Log → NICHT zustellen) ───────────────────
# BRIDGE_LOG zeigt auf einen Pfad UNTER einer regulären Datei (ENOTDIR) — der Audit-Write
# schlägt strukturell fehl, auch als root (kein chmod-Trick nötig).
touch "$tmp/log-blocker"
BROKENLOG="$tmp/log-blocker/sub/bridge.log"
before_inbox="$(wc -l < "$INBOX" | tr -d ' ')"
t "M3: ACCEPT-Audit kaputt → exit 3 (fail-closed, nicht REJECT 2)" "3" \
  "$(SSH_ORIGINAL_COMMAND='[alpha]@Bill: sollte nicht ankommen' DEV_TEAM_REGISTRY="$tmp/registry.json" BOBNET_PEERS="$tmp/peers.json" BRIDGE_LOG="$BROKENLOG" bash "$RECV" peerB >/dev/null 2>&1; echo $?)"
after_inbox="$(wc -l < "$INBOX" | tr -d ' ')"
t "M3: bei kaputtem Audit KEINE neue Inbox-Zeile (nicht zugestellt)" "0" "$((after_inbox-before_inbox))"
t "M3: Nachricht taucht nirgends in der Inbox auf" "0" "$(grep -c 'sollte nicht ankommen' "$INBOX")"

# ── Reject-Blätter + Stempel-Varianten (Review-M1 + Test-Gate-Backlog) ──────────────────────
SSH_ORIGINAL_COMMAND="$(printf '[alpha]@Bill: vor\rnach dem CR')" recv peerB >/dev/null 2>&1
t "CR (0x0D) wird gestrippt (Review-M1)" "1" "$(grep -c 'vornach dem CR' "$INBOX")"
t "leere Nachricht (kein SOC, stdin leer) → REJECT 2" "2" "$(recv peerB < /dev/null >/dev/null 2>&1; echo $?)"
t "nur Control-Chars → REJECT 2 (leer nach Sanitize)" "2" \
  "$(SSH_ORIGINAL_COMMAND="$(printf '\001\002\003')" recv peerB >/dev/null 2>&1; echo $?)"
t "Traversal-uid [../etc] → REJECT 2 (explizit)" "2" \
  "$(SSH_ORIGINAL_COMMAND='[../etc]@x: boese' recv peerB >/dev/null 2>&1; echo $?)"
SSH_ORIGINAL_COMMAND='[beta] ohne env-file' recv peerB >/dev/null 2>&1
t "uid ohne dev-team.env → Agent-Default Bob" "1" "$(grep -c '| @Bob | BRIDGE (peerB): ohne env-file' "$tmp/beta/_dev_team/standup/_inbox.md")"
SSH_ORIGINAL_COMMAND='[alpha]@Bill: vom plainpeer' recv plainpeer >/dev/null 2>&1
t "Peer ohne lead → Zeile OHNE Signatur" "1" "$(grep -cE 'BRIDGE \(plainpeer\): vom plainpeer$' "$INBOX")"
touch "$tmp/locked/standup/_inbox.md"; chmod 444 "$tmp/locked/standup/_inbox.md"
t "unschreibbare Inbox → REJECT 2 (Append fehlgeschlagen)" "2" \
  "$(SSH_ORIGINAL_COMMAND='[locked]@x: hi' recv peerB >/dev/null 2>&1; echo $?)"
chmod 644 "$tmp/locked/standup/_inbox.md"
ok "Audit: Append-Fehlschlag geloggt" grep -q 'REJECT: Append fehlgeschlagen' "$LOG"
# R1/#52: der ACCEPT-Eintrag kommt erst NACH dem erfolgreichen Append — schlägt der Append
# fehl, darf für DIESELBE Nachricht KEIN ACCEPT im Log stehen (sonst ACCEPT + anschließendes
# "REJECT: Append fehlgeschlagen" für dieselbe Nachricht, widersprüchlich).
t "R1: Append-Fehlschlag → kein ACCEPT im Log für dieselbe Nachricht" "0" \
  "$(grep -c 'ACCEPT.*target=\[locked\]@x' "$LOG")"

# ── L7/#51: Log-Spoofing-Schutz — Peer-Format + Display-Namen sanitizen ─────────────────────
t "L7: Peer mit Steuerzeichen/Sonderzeichen → REJECT 2" "2" \
  "$(SSH_ORIGINAL_COMMAND='[alpha]@Bill: hi' DEV_TEAM_REGISTRY="$tmp/registry.json" BOBNET_PEERS="$tmp/peers.json" BRIDGE_LOG="$LOG" bash "$RECV" "$(printf 'peerB\nFAKE | ACCEPT | peer=evil')" >/dev/null 2>&1; echo $?)"
loglines_before="$(wc -l < "$LOG" | tr -d ' ')"
SSH_ORIGINAL_COMMAND='[alpha]@Bill: hi' DEV_TEAM_REGISTRY="$tmp/registry.json" BOBNET_PEERS="$tmp/peers.json" BRIDGE_LOG="$LOG" bash "$RECV" "$(printf 'peerB\nFAKE-LINE')" >/dev/null 2>&1
loglines_after="$(wc -l < "$LOG" | tr -d ' ')"
t "L7: Peer-Newline erzeugt genau 1 neue Audit-Zeile (kein Log-Spoofing)" "1" "$((loglines_after-loglines_before))"

inbox_before="$(wc -l < "$INBOX" | tr -d ' ')"
SSH_ORIGINAL_COMMAND='[alpha]@Bill: via spoofpeer' recv spoofpeer >/dev/null 2>&1
inbox_after="$(wc -l < "$INBOX" | tr -d ' ')"
t "L7: peers.json-lead mit Newline erzeugt genau 1 neue Inbox-Zeile (kein Spoofing)" "1" "$((inbox_after-inbox_before))"
ok "L7: Inbox-Zeile trotzdem korrekt gestempelt" grep -q 'BRIDGE (spoofpeer): via spoofpeer' "$INBOX"

SSH_ORIGINAL_COMMAND='[alpha]@Bill: lang' recv longleadpeer >/dev/null 2>&1
t "L7: Peer-Lead-Signatur auf 64 Zeichen gecappt" "1" "$(grep -cE -- "— \(${longlead:0:64}@longleadpeer\)\$" "$INBOX")"
t "L7: ungecappte 100-Zeichen-Signatur NICHT vorhanden" "0" "$(grep -c -- "${longlead}@longleadpeer" "$INBOX")"

# ── Sender: Vor-Validierung + Auflösung ─────────────────────────────────────────────────────
t "send: ohne [uid]-Adressierung → exit 2 (lokal, vor Netz)" "2" \
  "$(BOBNET_PEERS="$tmp/peers.json" bash "$SEND" peerB "hallo ohne adresse" >/dev/null 2>&1; echo $?)"
t "send: unbekannter Peer → exit 2" "2" \
  "$(BOBNET_PEERS="$tmp/peers.json" bash "$SEND" niemand "[alpha] hi" >/dev/null 2>&1; echo $?)"
t "send: fehlende peers.json → exit 2" "2" \
  "$(BOBNET_PEERS="$tmp/nix.json" bash "$SEND" peerB "[alpha] hi" >/dev/null 2>&1; echo $?)"
t "send: usage → exit 2" "2" "$(bash "$SEND" peerB 2>/dev/null; echo $?)"

# Transport-Override: Zeile (geplättet) auf stdin, Platzhalter ersetzt (M5/#51: nur mit
# BRIDGE_TEST_MODE=1 aktiv — siehe die eigene M5-Sektion weiter unten für den Guard selbst)
BOBNET_PEERS="$tmp/peers.json" BRIDGE_TEST_MODE=1 BRIDGE_TRANSPORT_CMD="cat > $tmp/sent-{user}.txt" \
  bash "$SEND" peerB "$(printf '[alpha]@Bill: zeile1\nzeile2')" >/dev/null
t "send: Override bekommt geplättete Zeile" "[alpha]@Bill: zeile1 zeile2" "$(tr -d '\n' < "$tmp/sent-acme.txt")"
t "send: Remote-REJECT (rc 2) propagiert als 2" "2" \
  "$(BOBNET_PEERS="$tmp/peers.json" BRIDGE_TEST_MODE=1 BRIDGE_TRANSPORT_CMD="exit 2" bash "$SEND" peerB "[alpha] hi" >/dev/null 2>&1; echo $?)"
# #52: rc 3 (Empfänger-Infra-Fehler, seit M3/#51) muss UNTERSCHIEDLICH von rc 2 (REJECT)
# durchgereicht werden, nicht beide auf 2 zusammengefaltet.
t "send: Empfänger-Infra-Fehler (rc 3) propagiert als 3, nicht als 2" "3" \
  "$(BOBNET_PEERS="$tmp/peers.json" BRIDGE_TEST_MODE=1 BRIDGE_TRANSPORT_CMD="exit 3" bash "$SEND" peerB "[alpha] hi" >/dev/null 2>&1; echo $?)"

# ── ssh-Shim (PATH-Fake): exakte argv + STDIN + Fehlerzweige des ECHTEN ssh-Pfads ───────────
mkdir -p "$tmp/bin"
cat > "$tmp/bin/ssh" <<SH
#!/usr/bin/env bash
printf '%s\n' "\$@" > "$tmp/ssh-argv.txt"
cat > "$tmp/ssh-stdin.txt"
exit "\${FAKE_SSH_RC:-0}"
SH
chmod +x "$tmp/bin/ssh"

# M5/#51: BRIDGE_TRANSPORT_CMD wirkt NUR mit BRIDGE_TEST_MODE=1 (Shell-Injection-Schutz) —
# ohne TEST_MODE muss der normale forced/ssh-Pfad laufen (echter ssh-Aufruf, Override-Marker
# bleibt ungeschrieben), nicht der Override.
rm -f "$tmp/ssh-argv.txt" "$tmp/should-not-exist.txt"
PATH="$tmp/bin:$PATH" BOBNET_PEERS="$tmp/peers.json" BRIDGE_TRANSPORT_CMD="cat > $tmp/should-not-exist.txt" \
  bash "$SEND" peerB "[alpha]@Bill: M5 override ignoriert" >/dev/null 2>"$tmp/m5-warn.txt"
ok "M5: ohne TEST_MODE läuft der normale ssh-Pfad (argv geschrieben)" test -e "$tmp/ssh-argv.txt"
ok "M5: Override-Marker NICHT geschrieben (Override ignoriert)" test ! -e "$tmp/should-not-exist.txt"
ok "M5: Warnung auf stderr" grep -q 'BRIDGE_TEST_MODE' "$tmp/m5-warn.txt"
rm -f "$tmp/ssh-argv.txt" "$tmp/ssh-stdin.txt"

# H1 (#49): forced-Peer → Payload auf STDIN, KEIN Kommando in argv
PATH="$tmp/bin:$PATH" BOBNET_PEERS="$tmp/peers.json" bash "$SEND" peerB "[alpha]@Bill: echt per ssh" >/dev/null
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
  "$(PATH="$tmp/bin:$PATH" FAKE_SSH_RC=255 BOBNET_PEERS="$tmp/peers.json" bash "$SEND" peerB "[alpha] hi" >/dev/null 2>&1; echo $?)"
t "ssh rc=2 (Remote-REJECT) → exit 2" "2" \
  "$(PATH="$tmp/bin:$PATH" FAKE_SSH_RC=2 BOBNET_PEERS="$tmp/peers.json" bash "$SEND" peerB "[alpha] hi" >/dev/null 2>&1; echo $?)"
t "ssh rc=3 (Empfänger-Infra-Fehler) → exit 3, nicht 2" "3" \
  "$(PATH="$tmp/bin:$PATH" FAKE_SSH_RC=3 BOBNET_PEERS="$tmp/peers.json" bash "$SEND" peerB "[alpha] hi" >/dev/null 2>&1; echo $?)"

# ── Roundtrip ohne SSH: Sender-Override pipet in den Empfänger (stdin-Fallback) ─────────────
BOBNET_PEERS="$tmp/peers.json" BRIDGE_TEST_MODE=1 BRIDGE_TRANSPORT_CMD="DEV_TEAM_REGISTRY=$tmp/registry.json BOBNET_PEERS=$tmp/peers.json BRIDGE_LOG=$LOG bash $RECV peerB" \
  bash "$SEND" peerB "[alpha]@Bill: roundtrip komplett" >/dev/null
t "Roundtrip: Zeile landet in der Ziel-Inbox" "1" "$(grep -c 'BRIDGE (peerB): roundtrip komplett' "$INBOX")"

# ── L8/#51: Sender-Audit — append-only, ts·peer·bytes·rc, best-effort ───────────────────────
# Eigener Pfad (nicht die Default-Fallback-Datei) — sonst zählen hier auch die Audit-Zeilen
# aller vorherigen Sends in dieser Spec mit, die BOBNET_SEND_LOG/STANDUP_DIR nicht setzen.
SENDLOG="$tmp/explicit-send.log"
BOBNET_PEERS="$tmp/peers.json" BOBNET_SEND_LOG="$SENDLOG" BRIDGE_TEST_MODE=1 BRIDGE_TRANSPORT_CMD="exit 0" \
  bash "$SEND" peerB "[alpha]@Bill: send-audit test" >/dev/null
ok "L8: Sender-Audit-Datei geschrieben" test -s "$SENDLOG"
ok "L8: Sender-Audit nennt Peer" grep -q 'peer=peerB' "$SENDLOG"
ok "L8: Sender-Audit nennt rc=0" grep -q 'rc=0' "$SENDLOG"
t "L8: genau 1 Zeile pro Send" "1" "$(wc -l < "$SENDLOG" | tr -d ' ')"
BOBNET_PEERS="$tmp/peers.json" BOBNET_SEND_LOG="$SENDLOG" BRIDGE_TEST_MODE=1 BRIDGE_TRANSPORT_CMD="exit 2" \
  bash "$SEND" peerB "[alpha]@Bill: send-audit zweite Zeile" >/dev/null 2>&1
t "L8: 2. Send haengt an (append-only, 2 Zeilen)" "2" "$(wc -l < "$SENDLOG" | tr -d ' ')"
ok "L8: rc=2 (Remote-REJECT) im Audit sichtbar" grep -q 'rc=2' "$SENDLOG"

# Default-Auflösung: STANDUP_DIR gesetzt → dort; sonst neben der peers.json (symmetrisch zu
# bridge-receive.sh BRIDGE_LOG).
mkdir -p "$tmp/standup2"
STANDUP_DIR="$tmp/standup2" BOBNET_PEERS="$tmp/peers.json" BRIDGE_TEST_MODE=1 BRIDGE_TRANSPORT_CMD="exit 0" \
  bash "$SEND" peerB "[alpha] via standupdir" >/dev/null
ok "L8: Default nutzt STANDUP_DIR/bridge-send.log" test -s "$tmp/standup2/bridge-send.log"
env -u STANDUP_DIR BOBNET_PEERS="$tmp/peers.json" BRIDGE_TEST_MODE=1 BRIDGE_TRANSPORT_CMD="exit 0" \
  bash "$SEND" peerB "[alpha] ohne standupdir" >/dev/null
ok "L8: Fallback ohne STANDUP_DIR — neben der peers.json" test -s "$tmp/bridge-send.log"

echo "bridge_spec: $pass passed, $fail failed"
[ "$fail" = 0 ]
