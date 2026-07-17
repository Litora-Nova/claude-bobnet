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
#                       Größen-Vorprüfung: die Bytes werden — wo möglich (Base64) — aus der
#                       KODIERTEN Länge abgeschätzt (~Länge*3/4), BEVOR decodiert wird, damit
#                       ein überdimensionierter Anhang nicht erst voll decodiert werden muss,
#                       nur um verworfen zu werden (Codex-Review M6/#51, unbounded IO).
#   SCUT_MAIL_ATTACH_MAX_COUNT   max. Anzahl persistierter Anhänge PRO MAIL (Default 10);
#                       darüber hinausgehende werden übersprungen (bleiben im Postfach, Zeile
#                       vermerkt "N übersprungen"; M6/#51).
#   SCUT_MAIL_ATTACH_MAX_TOTAL   max. Bytes AGGREGIERT über alle Anhänge einer Mail (Default
#                       52428800 = 50MB); ab hier werden weitere Anhänge übersprungen, auch
#                       wenn sie einzeln unter SCUT_MAIL_ATTACH_MAX liegen (M6/#51).
#   SCUT_MAIL_BODY_MAX   max. Bytes für den persistierten Volltext (<prefix>-body.txt);
#                       Default 262144 (256 KB). Überschreitung wird an der UTF-8-Zeichengrenze
#                       gekürzt + im Volltext und in der Event-Zeile vermerkt (kein Fehler,
#                       der Digest in der Zeile bleibt wie bisher auf 400 Zeichen gecappt;
#                       M6/#51 — bisher hatte der persistierte Volltext GAR keinen Cap).
#   SCUT_MAIL_ATTACH_STRICT  Verhalten bei fehlgeschlagener Persistenz (Issue #50, Codex-H2):
#                       DEFAULT (unset/0) = best-effort: Mail wird zugestellt, Offset rückt vor,
#                       die Zeile trägt „Persistenz fehlgeschlagen"; RECOVERY = Anker manuell auf
#                       die letzte gute UID zurückdrehen (Runbook), nächster Poll liefert erneut.
#                       =1 STRICT: bei Persistenz-Fehler wird der Offset NICHT vorgerückt und der
#                       Poll gestoppt — die UID kommt automatisch beim nächsten Poll erneut (kein
#                       Anhang-Verlust). Preis: DAUER-Fehler (Disk voll) stallt den Kanal
#                       head-of-line (laut in stderr/Journal, kein stiller Verlust).
#   SCUT_MAIL_SENDERS_FILE   known-sender mapping (Issue #53): eine bekannte Absender-Adresse
#                       pro Zeile ("<adresse>" oder "<adresse> @Agent"), `#`-Kommentare/Leerzeilen
#                       ignoriert, Adress-Match case-insensitive. Match UND die Mail hat noch
#                       keinen Subject-Tag/Plus-Adress-Treffer → wird als "@<Agent>" (Default
#                       TEAM_LEAD, sonst der gemappte Agent) VOR den Text gestellt, landet also
#                       gerichtet in der Projekt-Inbox statt ungerichtet in der Review-Queue —
#                       die Haupt-Kundenmail kommt i. d. R. OHNE [uid]@Agent-Adressierung.
#                       Default (unset): $PROJECT_ROOT/_dev_team/team-rules/scut-mail.senders,
#                       falls PROJECT_ROOT gesetzt ist (Instanz-Daten, NIE ins Engine-Repo
#                       committen); fehlt die Datei oder ist sie leer → Verhalten unverändert
#                       (ungerichtet → Review-Queue, wie bisher). Niedrigste Priorität: greift
#                       NUR, wenn Subject-Tag UND Plus-Adresse nicht gezogen haben.
#   SCUT_MAIL_SENDERS_DEFAULT_AGENT   Agent für einen Treffer ohne explizites "@Agent" in der
#                       Mapping-Zeile. Default: $TEAM_LEAD (aus dev-team.env), sonst "Bob".
#   SCUT_MAIL_THREAD_MAP   In-Reply-To-Thread-Routing (Issue #54): jede Mail, die GERICHTET
#                       geroutet wird (Subject-Tag, Plus-Adresse oder Senders-Map — gleich welcher
#                       Mechanismus), hinterlässt ihre eigene Message-ID + das aufgelöste Ziel
#                       ("[uid]"/"@Agent"/beides) in dieser Map-Datei (Format je Zeile
#                       "<message-id><TAB><ziel>"). Eine EINGEHENDE Mail ohne eigenen Tag/Plus-
#                       Treffer, deren In-Reply-To ODER References-Header eine dieser Message-IDs
#                       referenziert, erbt automatisch dasselbe Ziel — auch ohne Senders-Map-
#                       Eintrag. Priorität: Subject-Tag > Plus-Adresse > Thread-Map > Senders-Map
#                       (eine laufende Antwortkette ist ein konkreteres Signal als ein statischer
#                       Senders-Map-Default). Default: $SECRETS/mail-threads.map (Kanal-Infra-
#                       State, KEINE Instanz-Daten wie SCUT_MAIL_SENDERS_FILE — lebt neben
#                       email_offset, gleiches Default-Muster, standardmäßig AN). Datei fehlt/ist
#                       leer -> einfach noch keine bekannten Threads (kein Fehler); Tests
#                       isolieren sich ueber einen expliziten Tmp-Pfad, wie bei email_offset ueblich.
#                       TRUST BOUNDARY (delta-gate review): In-Reply-To/References are unauthenticated
#                       email headers under the sender's control. Anyone who has SEEN a message-id
#                       (e.g. a prior reply in the same thread, or a forwarded/leaked mail) can craft
#                       a new message referencing it and inherit that thread's routing target — and
#                       since every directed mail re-registers its OWN message-id, a successful ride-
#                       along is self-reinforcing (their forged reply now seeds the map too). This is
#                       the SAME trust class as SCUT_MAIL_SENDERS_FILE (a static claim about "who
#                       this address is", not cryptographically verified) — no code change here, no
#                       auto-exec results from a routing decision either way. The structural fix
#                       (verifying thread continuity beyond a bare header match) is tracked as the
#                       inbound-injection hardening gate (#57), not part of this batch.
#   SCUT_MAIL_THREAD_MAP_MAXLINES   Rotation: die Map behält nur die letzten N Zeilen (Default
#                       500) — verhindert unbegrenztes Wachstum bei Dauerbetrieb.
#   SCUT_MAIL_EML_DIR   TESTMODUS: statt IMAP alle *.eml in diesem Ordner parsen (sortiert,
#                       kein Offset-Write) — macht Parsing/Triage ohne Server spec-bar.
#   SCUT_MAIL_EML_OFFSET_TEST   TESTMODUS-Zusatz (nur mit SCUT_MAIL_EML_DIR): 1 = pro Datei
#                       einen synthetischen Offset-Token ("emltest:NNN" statt "-") erzeugen,
#                       damit Specs die STRICT/Default-Offset-Semantik (rückt vor / hält)
#                       OHNE echten IMAP-Server prüfen können (Marvins Test-Seam, #51/L9).
#                       Wird in diesem Modus weiterhin NIE zurückgelesen — keine produktive
#                       Wirkung. Default(unset) bleibt exakt der bisherige EML-Testmodus
#                       (kein Offset-Write).
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

# #53: known-sender mapping — Instanz-Daten (nie im Engine-Repo), Default abgeleitet vom
# PROJECT_ROOT der (gesourcten) dev-team.env; Pfad + Default-Agent bleiben env-übersteuerbar
# (Specs setzen SCUT_MAIL_SENDERS_FILE direkt, ohne PROJECT_ROOT zu brauchen).
SENDERS_FILE="${SCUT_MAIL_SENDERS_FILE:-}"
[ -z "$SENDERS_FILE" ] && [ -n "${PROJECT_ROOT:-}" ] \
  && SENDERS_FILE="$PROJECT_ROOT/_dev_team/team-rules/scut-mail.senders"
SENDERS_DEFAULT_AGENT="${SCUT_MAIL_SENDERS_DEFAULT_AGENT:-${TEAM_LEAD:-Bob}}"

# #54: In-Reply-To-Thread-Map — Kanal-Infra-State (wie email_offset), keine Instanz-Daten.
THREAD_MAP="${SCUT_MAIL_THREAD_MAP:-$SECRETS/mail-threads.map}"
THREAD_MAP_MAXLINES="${SCUT_MAIL_THREAD_MAP_MAXLINES:-500}"

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
  parsed="$(SCUT_MAIL_EML_DIR="$EML_DIR" SCUT_MAIL_EML_OFFSET_TEST="${SCUT_MAIL_EML_OFFSET_TEST:-}" \
            MAIL_HOST="$HOST" MAIL_USER="$USER_" MAIL_PASS="$PASS" \
            MAIL_PORT="$PORT" MAIL_MAILBOX="$MAILBOX" MAIL_OFFSET_FILE="$OFFSET_FILE" \
            MAIL_ATTACH_DIR="${SCUT_MAIL_ATTACH_DIR:-}" MAIL_ATTACH_MAX="${SCUT_MAIL_ATTACH_MAX:-10485760}" \
            MAIL_BODY_MAX="${SCUT_MAIL_BODY_MAX:-262144}" \
            MAIL_ATTACH_MAX_COUNT="${SCUT_MAIL_ATTACH_MAX_COUNT:-10}" \
            MAIL_ATTACH_MAX_TOTAL="${SCUT_MAIL_ATTACH_MAX_TOTAL:-52428800}" \
            MAIL_SENDERS_FILE="$SENDERS_FILE" MAIL_SENDERS_DEFAULT_AGENT="$SENDERS_DEFAULT_AGENT" \
            MAIL_THREAD_MAP="$THREAD_MAP" MAIL_THREAD_MAP_MAXLINES="$THREAD_MAP_MAXLINES" \
            python3 - <<'PY'
import email, email.header, email.utils, glob, imaplib, os, re, sys, time, unicodedata

ATTACH_DIR = os.environ.get("MAIL_ATTACH_DIR", "")
ATTACH_MAX = int(os.environ.get("MAIL_ATTACH_MAX") or 10485760)
BODY_MAX = int(os.environ.get("MAIL_BODY_MAX") or 262144)
ATTACH_MAX_COUNT = int(os.environ.get("MAIL_ATTACH_MAX_COUNT") or 10)
ATTACH_MAX_TOTAL = int(os.environ.get("MAIL_ATTACH_MAX_TOTAL") or 52428800)

def fmt_size(n):
    return "%dMB" % (n // 1048576) if n >= 1048576 else "%dB" % n

def truncate_utf8(s, max_bytes):
    # An der Byte-Grenze schneiden, dann unvollständige Trailing-Bytes verwerfen (M6/#51:
    # der persistierte Volltext hatte bisher GAR keinen Cap).
    raw = s.encode("utf-8", "replace")
    if len(raw) <= max_bytes:
        return s, False
    return raw[:max_bytes].decode("utf-8", "ignore"), True

def estimate_encoded_bytes(part):
    # Größen-Vorprüfung VOR dem vollen Decode (M6/#51, unbounded IO): für Base64 lässt sich
    # die decodierte Größe aus der kodierten Länge abschätzen (~Länge*3/4), ohne zu decodieren.
    # Andere Transfer-Encodings (7bit/8bit/quoted-printable) schrumpfen beim Decode nie
    # wesentlich — die rohe Länge ist dort schon eine sichere Obergrenze.
    raw = part.get_payload(decode=False)
    if isinstance(raw, list):
        return 0
    raw_len = len(str(raw or "").encode("utf-8", "ignore"))
    enc = (part.get("Content-Transfer-Encoding") or "").strip().lower()
    return (raw_len * 3) // 4 if enc == "base64" else raw_len

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
    body_out, body_truncated = truncate_utf8(body, BODY_MAX)
    with open(os.path.join(ATTACH_DIR, "%s-body.txt" % prefix), "w",
              encoding="utf-8", errors="replace") as fh:
        fh.write("From: %s\nDate: %s\nSubject: %s\n\n%s" % (sender, date_hdr, subject, body_out))
        if body_truncated:
            fh.write("\n\n[... gekürzt, Volltext > %s ...]" % fmt_size(BODY_MAX))
    saved, seen = [], set()
    skipped_size = skipped_count = skipped_total = 0
    total_bytes = 0
    for part in atts:
        if len(saved) >= ATTACH_MAX_COUNT:
            skipped_count += 1
            continue
        # Vorprüfung aus der kodierten Länge, BEVOR decodiert wird (M6/#51) — ein
        # überdimensionierter Anhang muss so nie voll ins RAM decodiert werden, nur um
        # verworfen zu werden.
        est = estimate_encoded_bytes(part)
        if est > ATTACH_MAX:
            skipped_size += 1
            continue
        if total_bytes + est > ATTACH_MAX_TOTAL:
            skipped_total += 1
            continue
        data = part.get_payload(decode=True) or b""
        if len(data) > ATTACH_MAX:
            skipped_size += 1
            continue
        if total_bytes + len(data) > ATTACH_MAX_TOTAL:
            skipped_total += 1
            continue
        # Kollisions-Dedup NUR innerhalb der Mail (Review-A1); bewusst nicht gegen die
        # Disk, damit ein Batch-Retry idempotent überschreibt statt -2-Duplikate zu stapeln.
        fname = sanitize_name(part.get_filename())
        base, ext = os.path.splitext(fname)
        n = 1
        while fname in seen:
            n += 1
            fname = "%s-%d%s" % (base, n, ext)
        seen.add(fname)
        with open(os.path.join(ATTACH_DIR, "%s-%s" % (prefix, fname)), "wb") as fh:
            fh.write(data)
        saved.append("%s-%s" % (prefix, fname))
        total_bytes += len(data)
    note = " [Volltext: %s-body.txt" % prefix
    if body_truncated:
        note += " (gekürzt, > %s)" % fmt_size(BODY_MAX)
    if saved:
        note += " · Anhänge: " + (", ".join(saved) if len(saved) <= 3
                                  else "%d Dateien (%s-*)" % (len(saved), prefix))
    skip_notes = []
    if skipped_size:
        skip_notes.append("%d übersprungen (>%s, im Postfach)" % (skipped_size, fmt_size(ATTACH_MAX)))
    if skipped_count:
        skip_notes.append("%d übersprungen (>%d Anhänge/Mail, im Postfach)" % (skipped_count, ATTACH_MAX_COUNT))
    if skipped_total:
        skip_notes.append("%d übersprungen (Summe >%s, im Postfach)" % (skipped_total, fmt_size(ATTACH_MAX_TOTAL)))
    if skip_notes:
        note += " · " + " · ".join(skip_notes)
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

SENDERS_FILE = os.environ.get("MAIL_SENDERS_FILE", "")
SENDERS_DEFAULT_AGENT = os.environ.get("MAIL_SENDERS_DEFAULT_AGENT") or "Bob"

MSGID_RE = re.compile(r"<[^<>]+>")

def load_thread_map(path):
    # #54: "<message-id><TAB><ziel>" pro Zeile; kaputte/fremde Zeilen (kein Tab) werden
    # übersprungen statt den ganzen Poll zu crashen (Instanz-State, nicht vertrauenswürdiger
    # als jede andere Datei, die von außen wachsen kann).
    m = {}
    if not path:
        return m
    try:
        with open(path, encoding="utf-8") as fh:
            for raw in fh:
                s = raw.rstrip("\n")
                if not s or "\t" not in s:
                    continue
                mid, _, tgt = s.partition("\t")
                if mid and tgt:
                    m[mid] = tgt
    except OSError:
        pass
    return m

THREAD_MAP_FILE = os.environ.get("MAIL_THREAD_MAP", "")
THREAD_MAP_MAXLINES = int(os.environ.get("MAIL_THREAD_MAP_MAXLINES") or 500)
THREAD_MAP = load_thread_map(THREAD_MAP_FILE)

def thread_map_lookup(msg):
    # #54: In-Reply-To zuerst (der direkte Elternteil), dann References rückwärts (jüngster
    # zuerst) — beides sind laut RFC 2822 <message-id>-Listen. Erster Treffer in der Map gewinnt.
    if not THREAD_MAP:
        return ""
    ids = MSGID_RE.findall(msg.get("In-Reply-To", "") or "")
    ids += list(reversed(MSGID_RE.findall(msg.get("References", "") or "")))
    for mid in ids:
        tgt = THREAD_MAP.get(mid)
        if tgt:
            return tgt
    return ""

def thread_map_record(message_id, tag):
    # Nur bei einer ECHTEN Message-ID sinnvoll (die synthetischen Fallback-Keys im EML-Testmodus
    # ohne eigene Message-ID würden nie von einem In-Reply-To/References-Header referenziert).
    if not THREAD_MAP_FILE or not message_id or not tag:
        return
    try:
        d = os.path.dirname(THREAD_MAP_FILE)
        if d:
            os.makedirs(d, exist_ok=True)
        lines = []
        if os.path.exists(THREAD_MAP_FILE):
            with open(THREAD_MAP_FILE, encoding="utf-8") as fh:
                lines = fh.read().splitlines()
        lines.append("%s\t%s" % (message_id, tag))
        if len(lines) > THREAD_MAP_MAXLINES:
            lines = lines[-THREAD_MAP_MAXLINES:]
        with open(THREAD_MAP_FILE, "w", encoding="utf-8") as fh:
            fh.write("\n".join(lines) + "\n")
        THREAD_MAP[message_id] = tag  # im selben Poll-Lauf sofort sichtbar (Batch mit mehreren Mails)
    except OSError as e:
        print("email-channel: Thread-Map-Write fehlgeschlagen (%s) — Routing dieser Mail bleibt unberührt" % e,
              file=sys.stderr)

def extract_leading_tag(text):
    # Führendes "[uid]" und/oder "@Agent" am Textanfang extrahieren (gleiche Grammatik wie
    # emit_event() auf der Bash-Seite) — für die Thread-Map-Aufzeichnung brauchen wir das
    # AUFGELÖSTE Ziel, unabhängig davon, ob es aus dem Subject kam oder hier injiziert wurde.
    m = re.match(r"^\[[A-Za-z0-9_-]+\]", text)
    uid_tag = m.group(0) if m else ""
    rest = text[len(uid_tag):] if uid_tag else text
    m2 = re.match(r"^@[A-Za-z0-9_-]+", rest)
    agent_tag = m2.group(0) if m2 else ""
    return uid_tag + agent_tag

def known_sender_tag(addr):
    # #53: bekannte Absender-Adresse (Feld-Hauptfall: Kundenmail ohne [uid]@Agent-Tag) →
    # gerichtetes "@<Agent>" statt ungerichtet in die Review-Queue. NUR Fallback — line_for()
    # ruft das erst, wenn Subject-Tag UND Plus-Adresse leer geblieben sind. Kein uid im Tag
    # nötig: der Poller läuft pro Projekt (CONTEXT_UID), der Router adressiert "@Agent" ohne
    # [uid] an genau dieses Kontext-Bobiverse.
    if not SENDERS_FILE or not addr:
        return ""
    addr_l = addr.strip().lower()
    try:
        with open(SENDERS_FILE, encoding="utf-8") as fh:
            for raw in fh:
                s = raw.strip()
                if not s or s.startswith("#"):
                    continue
                parts = s.split(None, 1)
                if parts[0].strip().lower() != addr_l:
                    continue
                if len(parts) > 1 and parts[1].strip().startswith("@"):
                    return parts[1].split()[0]
                return "@" + SENDERS_DEFAULT_AGENT
    except OSError:
        return ""
    return ""

def line_for(key, msg, prefix):
    subject = dec_header(msg.get("Subject", "")) or "(kein Betreff)"
    body, atts = body_and_attachments(msg)
    frm = dec_header(msg.get("From", "")) or "email"
    name, addr = email.utils.parseaddr(frm)
    sender = norm(name or addr or "email")
    own_mid = norm(msg.get("Message-ID", ""))   # #54: nur eine ECHTE Message-ID taugt als Thread-Anker
    ext = own_mid or key
    try:
        ts = int(email.utils.parsedate_to_datetime(msg.get("Date", "")).timestamp())
    except Exception:
        ts = int(time.time())
    digest = norm(body)[:400]
    text = subject + (" — " + digest if digest else "")
    pfail = "0"   # 1 = geforderte Persistenz fehlgeschlagen (Bash-Seite entscheidet Offset, H2/#50)
    if ATTACH_DIR:
        # Fehler PRO MAIL degradieren (Review-A2/Test-Gate-Fund): ein Schreibfehler
        # (Disk voll, Rechte) darf nie den ganzen Poll-Batch versenken — die Mail wird
        # trotzdem zugestellt, die Dateien bleiben im Postfach und die Zeile sagt es.
        try:
            text += persist_mail(prefix, sender, msg.get("Date", ""), subject, body, atts)
        except Exception as e:
            print("email-channel: Persistenz fehlgeschlagen (%s) — Dateien bleiben im Postfach" % e,
                  file=sys.stderr)
            # N1/#51: bei 0 Anhängen scheiterte nur der body.txt-Write — "0 Anhänge im
            # Postfach" wäre dann eine irreführende Formulierung (es gibt ja keine).
            if atts:
                text += " [Persistenz fehlgeschlagen — %d Anhang/Anhänge im Postfach]" % len(atts)
            else:
                text += " [Persistenz fehlgeschlagen — Mailtext nicht abgelegt]"
            pfail = "1"
    elif atts:
        text += " [%d Anhang/Anhänge im Postfach]" % len(atts)
    if subject.startswith(("[", "@")):
        final_tag = extract_leading_tag(subject)
    else:
        # #54: Plus-Adresse > Thread-Map (laufende Antwortkette) > Senders-Map (statischer
        # Default) — eine erkannte Antwortkette ist ein konkreteres Signal als ein einmal
        # hinterlegter Absender-Default, darf ihn also überstimmen.
        final_tag = plus_tag(msg) or thread_map_lookup(msg) or known_sender_tag(addr)
        if final_tag:
            text = final_tag + " " + text
    thread_map_record(own_mid, final_tag)
    row = [key, ext, str(ts), sender, pfail, text]
    print("\t".join(f.replace("\t", " ") for f in row))

eml_dir = os.environ.get("SCUT_MAIL_EML_DIR", "")
if eml_dir:
    # L9/#51 Test-Seam: mit SCUT_MAIL_EML_OFFSET_TEST=1 einen synthetischen Offset-Token
    # statt "-" liefern, damit Specs die STRICT/Default-Offset-Semantik (Bash-Seite unten)
    # auch ohne echten IMAP-Server prüfen können. Wird hier nie zurückgelesen — der normale
    # EML-Testmodus (Default) bleibt exakt wie bisher offset-los.
    offset_seam = os.environ.get("SCUT_MAIL_EML_OFFSET_TEST", "") == "1"
    for i, path in enumerate(sorted(glob.glob(os.path.join(eml_dir, "*.eml"))), 1):
        with open(path, "rb") as fh:
            key = "emltest:%03d" % i if offset_seam else "-"
            line_for(key, email.message_from_bytes(fh.read()), "eml%03d" % i)
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
  local offtok ext ts sender pfail text rest _F
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
    cut_field; pfail="$_F"
    text="$rest"
    # H2/#50 STRICT (opt-in): geforderte Persistenz fehlgeschlagen → Offset NICHT vorrücken
    # und stoppen. Die UID wird beim nächsten Poll erneut geliefert (mit Anhängen, sobald das
    # Schreiben wieder klappt). Kein Emit hier → keine Doppelzustellung bei permanentem Fehler;
    # Preis: bei DAUER-Fehler (Disk voll) stallt der Kanal head-of-line (laut in stderr/Journal).
    # Default (STRICT!=1): best-effort — Emit + Offset vor, Zeile trägt den „Persistenz
    # fehlgeschlagen"-Vermerk; Recovery = Anker manuell zurückdrehen (Runbook).
    if [ "${SCUT_MAIL_ATTACH_STRICT:-0}" = 1 ] && [ "$pfail" = 1 ]; then
      echo "email-channel: STRICT — Persistenz fehlgeschlagen, Offset NICHT vorgerückt (UID kommt nächsten Poll erneut)" >&2
      break
    fi
    emit_event "email" "$ext" "$ts" "$sender" "$text"
    # Offset erst NACH dem Emit fortschreiben (at-least-once, wie telegram.sh).
    # if statt &&-Kurzschluss: der falsy Guard (EML-Modus) darf nicht als rc der
    # letzten Loop-Iteration nach außen lecken (poll_once wäre sonst faelschlich rot).
    if [ "$offtok" != "-" ]; then printf '%s\n' "$offtok" > "$OFFSET_FILE"; fi
  done <<< "$parsed"
}

[ -z "$EML_DIR" ] && mkdir -p "$(dirname "$OFFSET_FILE")" 2>/dev/null

if [ -n "$EML_DIR" ] || [ "$ONESHOT" = 1 ]; then
  poll_once
else
  echo "email-channel: polle $MAILBOX@$HOST alle ${INTERVAL}s → normalisierte Events auf stdout" >&2
  while true; do poll_once || sleep 3; sleep "$INTERVAL"; done
fi
