#!/usr/bin/env bash
# tests/telegram_channel_spec.sh — scripts/channels/telegram.sh (Riker-Finding, #59-Delta).
#
# Vorher gab es KEINEN Spec für diesen Adapter — beim Bau eines minimalen Testpfads für die
# sender-Whitespace-Normalisierung (#57-Follow-up) kam ein eigenständiger, kritischer Fund
# ans Licht: `poll_once()` piped die Telegram-API-Antwort in einen `python3 - <<'PY'`-Block.
# Das ist ein Stdin-Konflikt — `python3 -` liest sein PROGRAMM aus stdin, der Heredoc IST also
# stdin, und ist beim Start des Scripts bereits konsumiert. `sys.stdin`/`json.load(sys.stdin)`
# im Skript bekam dadurch NIE die gepipete Antwort, sondern immer EOF/leer — jede echte Antwort
# wurde still verworfen (leerer `parsed`, kein Crash, kein sichtbarer Fehler). Gefixt via
# Env-Var + `os.environ[...]` (dasselbe etablierte Muster wie email.sh). Dieser Spec exerciert
# den Adapter jetzt über den TESTMODUS `SCUT_TG_FAKE_RESPONSE_FILE` (analog email.sh
# `SCUT_MAIL_EML_DIR`) — kein echter Bot-Token/Netzzugriff nötig.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN="$HERE/../scripts/channels/telegram.sh"
pass=0; fail=0
t(){ local d="$1" exp="$2" got="$3"; if [ "$got" = "$exp" ]; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL: $d — erwartet '$exp', bekam '$got'"; fi; }
ok(){ local d="$1"; shift; if "$@" >/dev/null 2>&1; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL: $d"; fi; }

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
ok "bash -n sauber" bash -n "$BIN"

secrets="$tmp/.secrets"; mkdir -p "$secrets"
echo "dummy-token" > "$secrets/telegram_token"
echo "12345" > "$secrets/telegram_chat_id"

run_tg() { # run_tg <fake-response-file> — pollt einmal, gibt TSV auf stdout aus
  SCUT_SECRETS_DIR="$secrets" SCUT_TG_FAKE_RESPONSE_FILE="$1" SCUT_TG_ONESHOT=1 bash "$BIN" 2>/dev/null
}

# ── (1) Kritischer Fund: die API-Antwort wird überhaupt geparst (nicht still verworfen) ────
cat > "$tmp/basic.json" <<'JSON'
{"ok":true,"result":[
  {"update_id":100,"message":{"message_id":1,"date":1700000000,"chat":{"id":12345},"from":{"username":"kunde_x"},"text":"[acme]@Bill hallo"}}
]}
JSON
out1="$(run_tg "$tmp/basic.json")"
t "(1) getUpdates-Antwort wird geparst → 1 Event (Regression: Stdin-Konflikt-Fix)" "1" "$(printf '%s\n' "$out1" | grep -c .)"
t "(1) channel=telegram" "telegram" "$(printf '%s\n' "$out1" | cut -f1)"
t "(1) 6 TSV-Felder (Router-Kontrakt)" "6" "$(printf '%s\n' "$out1" | awk -F'\t' '{print NF}')"
t "(1) sender = username (Priorität vor first_name)" "kunde_x" "$(printf '%s\n' "$out1" | cut -f4)"
t "(1) target = [acme]@Bill (führendes [uid]+@Agent extrahiert)" "[acme]@Bill" "$(printf '%s\n' "$out1" | cut -f5)"
t "(1) text = Rest nach Target" "hallo" "$(printf '%s\n' "$out1" | cut -f6)"

# ── (2) #57-Follow-up: sender-Feld wird whitespace-normalisiert wie txt ────────────────────
printf '{"ok":true,"result":[{"update_id":200,"message":{"message_id":2,"date":1700000001,"chat":{"id":12345},"from":{"first_name":"Bad\\tName\\nWith\\r\\nBreaks"},"text":"kein Tag hier"}}]}' > "$tmp/messy-sender.json"
out2="$(run_tg "$tmp/messy-sender.json")"
t "(2) messy first_name (Tab/LF/CR) wird zu EINEM sauberen sender-Feld kollabiert" "Bad Name With Breaks" "$(printf '%s\n' "$out2" | cut -f4)"
t "(2) username fehlt → Fallback auf (normalisiertes) first_name" "Bad Name With Breaks" "$(printf '%s\n' "$out2" | cut -f4)"

# ── (3) ohne username UND first_name → Fallback 'telegram' ────────────────────────────────
printf '{"ok":true,"result":[{"update_id":300,"message":{"message_id":3,"date":1700000002,"chat":{"id":12345},"from":{},"text":"anonym"}}]}' > "$tmp/no-from.json"
out3="$(run_tg "$tmp/no-from.json")"
t "(3) weder username noch first_name → sender-Fallback 'telegram'" "telegram" "$(printf '%s\n' "$out3" | cut -f4)"

# ── (4) Chat-ID-Filter: fremder Chat wird NICHT emittiert ─────────────────────────────────
printf '{"ok":true,"result":[{"update_id":400,"message":{"message_id":4,"date":1700000003,"chat":{"id":99999},"from":{"username":"fremd"},"text":"nicht unser Chat"}}]}' > "$tmp/wrong-chat.json"
out4="$(run_tg "$tmp/wrong-chat.json")"
t "(4) Nachricht aus fremdem Chat wird NICHT emittiert" "0" "$(printf '%s\n' "$out4" | grep -c .)"
t "(4) ... Offset rückt trotzdem fort (kein Endlos-Reprocess)" "401" "$(cat "$secrets/telegram_offset")"

# ── (5) mehrere Updates in EINER Antwort → mehrere Zeilen, Offset = höchste update_id + 1 ──
cat > "$tmp/multi.json" <<'JSON'
{"ok":true,"result":[
  {"update_id":500,"message":{"message_id":5,"date":1700000004,"chat":{"id":12345},"from":{"username":"a"},"text":"eins"}},
  {"update_id":501,"message":{"message_id":6,"date":1700000005,"chat":{"id":12345},"from":{"username":"b"},"text":"zwei"}}
]}
JSON
out5="$(run_tg "$tmp/multi.json")"
t "(5) mehrere Updates → mehrere Events" "2" "$(printf '%s\n' "$out5" | grep -c .)"
t "(5) Offset rückt auf höchste update_id + 1 vor" "502" "$(cat "$secrets/telegram_offset")"

# ── (6) leere Antwort ('' oder kein 'result') → kein Crash, kein Event ────────────────────
printf '' > "$tmp/empty.json"
out6="$(run_tg "$tmp/empty.json")"
t "(6) leere Antwort → keine Events, kein Crash" "0" "$(printf '%s\n' "$out6" | grep -c .)"

printf '{"ok":true}' > "$tmp/no-result.json"
out6b="$(run_tg "$tmp/no-result.json")"
t "(6b) Antwort ohne 'result'-Feld → keine Events, kein Crash" "0" "$(printf '%s\n' "$out6b" | grep -c .)"

# ── (7) kaputtes JSON → kein Crash (rc bleibt egal, Hauptsache kein Absturz/Hänger) ────────
printf 'das ist kein JSON' > "$tmp/broken.json"
ok "(7) kaputtes JSON crasht den Adapter nicht" bash -c "SCUT_SECRETS_DIR='$secrets' SCUT_TG_FAKE_RESPONSE_FILE='$tmp/broken.json' SCUT_TG_ONESHOT=1 bash '$BIN'"

echo "telegram_channel_spec: $pass passed, $fail failed"
[ "$fail" = 0 ]
