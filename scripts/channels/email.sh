#!/usr/bin/env bash
# channels/email.sh — SCUT-Channel-Adapter: Email/IMAP → normalisiertes Event (FUNKTIONAL).
#
# Pollt ein IMAP-Postfach (readonly, non-destruktiv) und emittiert pro neuer Mail EINE
# normalisierte Event-Zeile auf stdout (TSV, 6 Felder — siehe scut-router.sh). Pipe in den Router:
#
#     scripts/channels/email.sh | scripts/scut-router.sh
#
# Target-Extraktion (Triage-Vorstufe; Router entscheidet final):
#   1. führendes "[<uid>]" und/oder "@<Agent>" im SUBJECT (z.B. "[acme]@Bill: Key rotieren")
#   2. sonst Plus-Adresse im To/Cc (team+acme@example.com → [acme] · team+acme-bill@… → [acme]@Bill)
#   3. kein Treffer → target leer (= ungerichtet → Review-Queue)
#
# Event-Text = "<Subject> — <Body-Auszug>" (text/plain bevorzugt, whitespace-normalisiert).
# Attachments werden in v1 NICHT gespeichert, nur gezählt ("[N Anhang/Anhänge im Postfach]").
#
# Secrets/Env (Präzedenz: Env-Var > Datei in SCUT_SECRETS_DIR > Default):
#   SCUT_MAIL_HOST / email_host        IMAP-Host (PFLICHT)
#   SCUT_MAIL_USER / email_user        Login (PFLICHT)
#   SCUT_MAIL_PASS / email_pass        Passwort (PFLICHT — Datei empfohlen, nie committen)
#   SCUT_MAIL_PORT / email_port        Default 993 (IMAPS)
#   SCUT_MAIL_MAILBOX / email_mailbox  Default INBOX
#   SCUT_MAIL_OFFSET_FILE              Default $SCUT_SECRETS_DIR/email_offset
#                                      (Format "<uidvalidity>:<letzte uid>"; UIDVALIDITY-Wechsel
#                                       resettet den Offset — Dedupe-Anker analog telegram_offset)
#   SCUT_MAIL_ONESHOT   1 = einmal pollen + raus (Tests/Cron); sonst Dauerschleife.
#   SCUT_MAIL_POLL_INTERVAL   Sekunden zwischen Polls in der Dauerschleife (Default 120).
#   SCUT_MAIL_BACKFILL  1 = beim Erstlauf (kein Offset-File) ALLE Altmails zustellen.
#                       Default: Erstlauf setzt nur den Offset-Anker auf die höchste UID und
#                       stellt NICHTS zu — verhindert die Altmail-Flut (Betriebs-Learning
#                       aus dem ersten produktiven projekt-lokalen Poller, PO-Fleet 2026-06).
#   SCUT_MAIL_ATTACH_DIR   OPT-IN Persistenz (Issue #46, Feld-Muster „Digest+Volltext-Duo"):
#                       pro Mail Volltext als <prefix>-body.txt + jeden Anhang als
#                       <prefix>-<ascii-sanitierter Name> in diesen Ordner (Empfehlung:
#                       <projekt-standup>/_inbox/mail — dann zählt inbox-watch die Drops mit);
#                       die Event-Zeile referenziert die Dateien. Unset = v1-Verhalten
#                       (Anhänge nur gezählt, bleiben im Postfach).
#   SCUT_MAIL_ATTACH_MAX   max. Bytes pro Anhang (Default 10485760 = 10MB); größere werden
#                       übersprungen und in der Zeile vermerkt (bleiben im Postfach).
#   SCUT_MAIL_EML_DIR   TESTMODUS: statt IMAP alle *.eml in diesem Ordner parsen (sortiert,
#                       kein Offset-Write) — macht Parsing/Triage ohne Server spec-bar.
#
# Host-Verdrahtung (Instanz-Seite, analog scut-poll): systemd-Template pro Projekt, Env aus
# dev-team.env, CONTEXT_UID=<uid> für den Router. Secrets/Enable = human-only (T4).
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENGINE_ROOT="${ENGINE_ROOT:-$(cd "$DIR/../.." && pwd)}"
SECRETS="${SCUT_SECRETS_DIR:-$ENGINE_ROOT/.secrets}"

if [ "${1:-}" = "--demo" ]; then
  now="$(date +%s)"
  printf 'email\t<msgid-1@x>\t%s\textern\t[acme]@Bill\tBitte den Vertrag gegenlesen\n' "$now"
  printf 'email\t<msgid-2@x>\t%s\tkunde\t\tAllgemeine Anfrage ohne Adressaten\n' "$now"
  exit 0
fi

# cred <envvar> <secfile> [default] — Env-Var schlägt Secrets-Datei schlägt Default.
cred() {
  local v="${!1:-}"
  [ -n "$v" ] && { printf '%s' "$v"; return; }
  [ -f "$SECRETS/$2" ] && { tr -d '\n' < "$SECRETS/$2"; return; }
  printf '%s' "${3:-}"
}

EML_DIR="${SCUT_MAIL_EML_DIR:-}"
HOST="$(cred SCUT_MAIL_HOST email_host)"
USER_="$(cred SCUT_MAIL_USER email_user)"
PASS="$(cred SCUT_MAIL_PASS email_pass)"
PORT="$(cred SCUT_MAIL_PORT email_port 993)"
MAILBOX="$(cred SCUT_MAIL_MAILBOX email_mailbox INBOX)"
OFFSET_FILE="${SCUT_MAIL_OFFSET_FILE:-$SECRETS/email_offset}"
ONESHOT="${SCUT_MAIL_ONESHOT:-0}"
INTERVAL="${SCUT_MAIL_POLL_INTERVAL:-120}"

if [ -z "$EML_DIR" ] && { [ -z "$HOST" ] || [ -z "$USER_" ] || [ -z "$PASS" ]; }; then
  echo "email-channel: SCUT_MAIL_HOST/USER/PASS fehlen (Env oder $SECRETS/email_*)" >&2
  exit 1
fi

# Erstlauf-Anker: ohne Offset-File NICHT das ganze Postfach zustellen (Altmail-Flut),
# sondern nur die höchste UID als Anker schreiben. SCUT_MAIL_BACKFILL=1 überspringt das.
if [ -z "$EML_DIR" ] && [ ! -f "$OFFSET_FILE" ] && [ "${SCUT_MAIL_BACKFILL:-0}" != 1 ]; then
  anchor="$(MAIL_HOST="$HOST" MAIL_USER="$USER_" MAIL_PASS="$PASS" MAIL_PORT="$PORT" \
            MAIL_MAILBOX="$MAILBOX" python3 - <<'PY'
import imaplib, os
M = imaplib.IMAP4_SSL(os.environ["MAIL_HOST"], int(os.environ["MAIL_PORT"]))
try:
    M.login(os.environ["MAIL_USER"], os.environ["MAIL_PASS"])
    M.select(os.environ["MAIL_MAILBOX"], readonly=True)
    uidval = (M.response("UIDVALIDITY")[1][0] or b"").decode()
    typ, data = M.uid("search", None, "ALL")
    uids = [int(u) for u in (data[0] or b"").split()]
    print("%s:%d" % (uidval, max(uids) if uids else 0))
finally:
    try:
        M.logout()
    except Exception:
        pass
PY
)" || { echo "email-channel: Offset-Init fehlgeschlagen (IMAP nicht erreichbar?)" >&2; exit 1; }
  mkdir -p "$(dirname "$OFFSET_FILE")"
  printf '%s\n' "$anchor" > "$OFFSET_FILE"
  echo "email-channel: Erstlauf — Offset-Anker $anchor gesetzt, Altmails übersprungen (SCUT_MAIL_BACKFILL=1 stellt stattdessen ab Anfang zu)" >&2
fi

# emit_event <channel> <ext_id> <ts> <sender> <rawtext>
#   extrahiert führendes [uid] und/oder @Agent → target; gibt normalisierte TSV-Zeile aus.
#   (Variante von channels/telegram.sh — BEWUSSTE Abweichung: nach @Agent wird auch ein
#    Doppelpunkt gestrippt ([[:space:]:]* statt [[:space:]]*), weil Email-Betreffs
#    "[uid]@Agent: Text" schreiben. Bei einem Refactor auf einen geteilten Helper den
#    Doppelpunkt-Strip als Parameter mitnehmen — sonst stille Regression.)
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

# poll_once — holt neue Mails (IMAP oder EML-Testordner) als Roh-Zeilen
#   "<uidvalidity>:<uid>\t<ext_id>\t<ts>\t<sender>\t<text>", emittiert Events, schreibt Offset.
poll_once() {
  local parsed
  parsed="$(SCUT_MAIL_EML_DIR="$EML_DIR" MAIL_HOST="$HOST" MAIL_USER="$USER_" MAIL_PASS="$PASS" \
            MAIL_PORT="$PORT" MAIL_MAILBOX="$MAILBOX" MAIL_OFFSET_FILE="$OFFSET_FILE" \
            MAIL_ATTACH_DIR="${SCUT_MAIL_ATTACH_DIR:-}" MAIL_ATTACH_MAX="${SCUT_MAIL_ATTACH_MAX:-10485760}" \
            python3 - <<'PY'
import email, email.header, email.utils, glob, imaplib, os, re, sys, time, unicodedata

ATTACH_DIR = os.environ.get("MAIL_ATTACH_DIR", "")
ATTACH_MAX = int(os.environ.get("MAIL_ATTACH_MAX") or 10485760)

def norm(s):
    return " ".join(str(s or "").split())

def dec_header(raw):
    parts = email.header.decode_header(raw or "")
    out = []
    for val, enc in parts:
        if isinstance(val, bytes):
            try:
                out.append(val.decode(enc or "utf-8", "replace"))
            except LookupError:
                out.append(val.decode("utf-8", "replace"))
        else:
            out.append(val)
    return norm("".join(out))

def body_and_attachments(msg):
    body, atts = "", []
    for part in msg.walk():
        if part.get_content_maintype() == "multipart":
            continue
        if part.get_filename():
            atts.append(part)
            continue
        if part.get_content_type() == "text/plain" and not body:
            payload = part.get_payload(decode=True) or b""
            body = payload.decode(part.get_content_charset() or "utf-8", "replace")
    if not body and not msg.is_multipart():
        payload = msg.get_payload(decode=True) or b""
        body = payload.decode(msg.get_content_charset() or "utf-8", "replace")
    return body, atts

def sanitize_name(name):
    # ASCII-Sanitize (Feld-Learning: Umlaut-Falle in Anhangs-Namen)
    name = unicodedata.normalize("NFKD", str(name or "")).encode("ascii", "ignore").decode()
    name = re.sub(r"[^A-Za-z0-9._-]+", "_", name).strip("._")
    return (name or "anhang")[:80]

def persist_mail(prefix, sender, date_hdr, subject, body, atts):
    # Digest+Volltext-Duo: Volltext + Anhänge als Dateien, Rückgabe = Zeilen-Suffix.
    os.makedirs(ATTACH_DIR, exist_ok=True)
    with open(os.path.join(ATTACH_DIR, "%s-body.txt" % prefix), "w",
              encoding="utf-8", errors="replace") as fh:
        fh.write("From: %s\nDate: %s\nSubject: %s\n\n%s" % (sender, date_hdr, subject, body))
    saved, skipped = [], 0
    for part in atts:
        data = part.get_payload(decode=True) or b""
        if len(data) > ATTACH_MAX:
            skipped += 1
            continue
        with open(os.path.join(ATTACH_DIR, "%s-%s" % (prefix, sanitize_name(part.get_filename()))),
                  "wb") as fh:
            fh.write(data)
        saved.append("%s-%s" % (prefix, sanitize_name(part.get_filename())))
    note = " [Volltext: %s-body.txt" % prefix
    if saved:
        note += " · Anhänge: " + (", ".join(saved) if len(saved) <= 3
                                  else "%d Dateien (%s-*)" % (len(saved), prefix))
    if skipped:
        cap = "%dMB" % (ATTACH_MAX // 1048576) if ATTACH_MAX >= 1048576 else "%dB" % ATTACH_MAX
        note += " · %d übersprungen (>%s, im Postfach)" % (skipped, cap)
    return note + "]"

PLUS_RE = re.compile(r"[A-Za-z0-9._%-]+\+([A-Za-z0-9_-]+)@")

def plus_tag(msg):
    for hdr in ("To", "Cc", "Delivered-To"):
        m = PLUS_RE.search(msg.get(hdr, "") or "")
        if m:
            tag = m.group(1)
            uid, _, agent = tag.partition("-")
            t = "[%s]" % uid
            if agent:
                t += "@" + agent[:1].upper() + agent[1:]
            return t
    return ""

def line_for(key, msg, prefix):
    subject = dec_header(msg.get("Subject", "")) or "(kein Betreff)"
    body, atts = body_and_attachments(msg)
    frm = dec_header(msg.get("From", "")) or "email"
    name, addr = email.utils.parseaddr(frm)
    sender = norm(name or addr or "email")
    ext = norm(msg.get("Message-ID", "")) or key
    try:
        ts = int(email.utils.parsedate_to_datetime(msg.get("Date", "")).timestamp())
    except Exception:
        ts = int(time.time())
    digest = norm(body)[:400]
    text = subject + (" — " + digest if digest else "")
    if ATTACH_DIR:
        text += persist_mail(prefix, sender, msg.get("Date", ""), subject, body, atts)
    elif atts:
        text += " [%d Anhang/Anhänge im Postfach]" % len(atts)
    if not subject.startswith(("[", "@")):
        tag = plus_tag(msg)
        if tag:
            text = tag + " " + text
    row = [key, ext, str(ts), sender, text]
    print("\t".join(f.replace("\t", " ") for f in row))

eml_dir = os.environ.get("SCUT_MAIL_EML_DIR", "")
if eml_dir:
    for i, path in enumerate(sorted(glob.glob(os.path.join(eml_dir, "*.eml"))), 1):
        with open(path, "rb") as fh:
            line_for("-", email.message_from_bytes(fh.read()), "eml%03d" % i)
    sys.exit(0)

off_file = os.environ["MAIL_OFFSET_FILE"]
try:
    with open(off_file) as fh:
        off_val, _, off_uid = fh.read().strip().partition(":")
        off_val, off_uid = off_val, int(off_uid or 0)
except Exception:
    off_val, off_uid = "", 0

M = imaplib.IMAP4_SSL(os.environ["MAIL_HOST"], int(os.environ["MAIL_PORT"]))
try:
    M.login(os.environ["MAIL_USER"], os.environ["MAIL_PASS"])
    M.select(os.environ["MAIL_MAILBOX"], readonly=True)
    uidval = (M.response("UIDVALIDITY")[1][0] or b"").decode()
    if uidval != off_val:
        off_uid = 0  # Mailbox neu aufgebaut → Offset-Anker ungültig
    typ, data = M.uid("search", None, "UID", "%d:*" % (off_uid + 1))
    uids = [int(u) for u in (data[0] or b"").split() if int(u) > off_uid]
    for uid in sorted(uids):
        typ, fetched = M.uid("fetch", str(uid), "(BODY.PEEK[])")
        raw = next((p[1] for p in fetched if isinstance(p, tuple)), None)
        if raw is None:
            continue
        line_for("%s:%d" % (uidval, uid), email.message_from_bytes(raw), "%05d" % uid)
finally:
    try:
        M.logout()
    except Exception:
        pass
PY
)" || return 1
  [ -z "$parsed" ] && return 0
  local offtok ext ts sender text rest _F
  cut_field() {
    case "$rest" in
      *$'\t'*) _F="${rest%%$'\t'*}"; rest="${rest#*$'\t'}";;
      *)       _F="$rest";          rest="";;
    esac
  }
  while IFS= read -r line || [ -n "$line" ]; do
    [ -z "$line" ] && continue
    rest="$line"
    cut_field; offtok="$_F"
    cut_field; ext="$_F"
    cut_field; ts="$_F"
    cut_field; sender="$_F"
    text="$rest"
    emit_event "email" "$ext" "$ts" "$sender" "$text"
    # Offset erst NACH dem Emit fortschreiben (at-least-once, wie telegram.sh)
    [ "$offtok" != "-" ] && printf '%s\n' "$offtok" > "$OFFSET_FILE"
  done <<< "$parsed"
}

[ -z "$EML_DIR" ] && mkdir -p "$(dirname "$OFFSET_FILE")" 2>/dev/null

if [ -n "$EML_DIR" ] || [ "$ONESHOT" = 1 ]; then
  poll_once
else
  echo "email-channel: polle $MAILBOX@$HOST alle ${INTERVAL}s → normalisierte Events auf stdout" >&2
  while true; do poll_once || sleep 3; sleep "$INTERVAL"; done
fi
