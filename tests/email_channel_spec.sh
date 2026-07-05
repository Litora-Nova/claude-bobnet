#!/usr/bin/env bash
# tests/email_channel_spec.sh — scripts/channels/email.sh (IMAP-Adapter; EML-Testmodus, kein Server).
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN="$HERE/../scripts/channels/email.sh"
ROUTER="$HERE/../scripts/scut-router.sh"
pass=0; fail=0
t(){ local d="$1" exp="$2" got="$3"; if [ "$got" = "$exp" ]; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL: $d — erwartet '$exp', bekam '$got'"; fi; }
ok(){ local d="$1"; shift; if "$@" >/dev/null 2>&1; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL: $d"; fi; }

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
ok "bash -n sauber" bash -n "$BIN"

# --demo: 2 wohlgeformte Events (6 TSV-Felder, channel=email)
demo="$(bash "$BIN" --demo)"
t "--demo: 2 Events" "2" "$(printf '%s\n' "$demo" | wc -l | tr -d ' ')"
t "--demo: 6 TSV-Felder" "6" "$(printf '%s\n' "$demo" | head -1 | awk -F'\t' '{print NF}')"
t "--demo: channel=email" "email" "$(printf '%s\n' "$demo" | head -1 | cut -f1)"

# EML-Fixtures (Testmodus: SCUT_MAIL_EML_DIR statt IMAP)
eml="$tmp/eml"; mkdir -p "$eml"
cat > "$eml/01-subject-tag.eml" <<'EOF'
From: Kunde X <kunde@example.com>
To: team@example.com
Subject: [acme]@Bill: Vertrag gegenlesen
Message-ID: <a1@example.com>
Date: Fri, 04 Jul 2026 10:00:00 +0200

Bitte Absatz 3 pruefen.
Zweite Zeile.
EOF
cat > "$eml/02-ungerichtet.eml" <<'EOF'
From: kunde@example.com
To: team@example.com
Subject: Allgemeine Anfrage
Message-ID: <a2@example.com>
Date: Fri, 04 Jul 2026 10:01:00 +0200

Wer kann helfen?
EOF
cat > "$eml/03-plus-adresse.eml" <<'EOF'
From: partner@example.com
To: team+acme-bill@example.com
Subject: Rechnung offen
Message-ID: <a3@example.com>
Date: Fri, 04 Jul 2026 10:02:00 +0200

Mahnung Nr. 2.
EOF
cat > "$eml/04-anhang.eml" <<'EOF'
From: kunde@example.com
To: team+acme@example.com
Subject: Unterlagen
Message-ID: <a4@example.com>
Date: Fri, 04 Jul 2026 10:03:00 +0200
MIME-Version: 1.0
Content-Type: multipart/mixed; boundary="B"

--B
Content-Type: text/plain

Siehe Anhang.
--B
Content-Type: application/pdf
Content-Disposition: attachment; filename="doc.pdf"

JVBERi0=
--B--
EOF

out="$(SCUT_MAIL_EML_DIR="$eml" bash "$BIN")"
t "EML: 4 Events" "4" "$(printf '%s\n' "$out" | wc -l | tr -d ' ')"
l1="$(printf '%s\n' "$out" | sed -n 1p)"; l2="$(printf '%s\n' "$out" | sed -n 2p)"
l3="$(printf '%s\n' "$out" | sed -n 3p)"; l4="$(printf '%s\n' "$out" | sed -n 4p)"

# Subject-Tag → target; Text = "Subject — Body" (geplättet, Tag/Doppelpunkt gestrippt)
t "Subject-Tag: target" "[acme]@Bill" "$(printf '%s\n' "$l1" | cut -f5)"
t "Subject-Tag: Text geplättet + gestrippt" \
  "Vertrag gegenlesen — Bitte Absatz 3 pruefen. Zweite Zeile." "$(printf '%s\n' "$l1" | cut -f6)"
t "ext_id = Message-ID" "<a1@example.com>" "$(printf '%s\n' "$l1" | cut -f2)"
ok "ts numerisch" grep -qE '^[0-9]+$' <<< "$(printf '%s\n' "$l1" | cut -f3)"
t "sender = From-Displayname" "Kunde X" "$(printf '%s\n' "$l1" | cut -f4)"

# ohne Tag/Plus → ungerichtet (target leer)
t "ungerichtet: target leer" "" "$(printf '%s\n' "$l2" | cut -f5)"

# Plus-Adresse team+acme-bill@ → [acme]@Bill (nur wenn Subject keinen Tag hat)
t "Plus-Adresse: target" "[acme]@Bill" "$(printf '%s\n' "$l3" | cut -f5)"

# Plus-Adresse nur uid + Attachment-Zählung im Text
t "Plus-Adresse uid-only: target" "[acme]" "$(printf '%s\n' "$l4" | cut -f5)"
t "Anhang gezählt, nicht gespeichert" "1" "$(printf '%s\n' "$l4" | cut -f6 | grep -c '\[1 Anhang/Anhänge im Postfach\]')"

# ── Attachment-Persistenz (#46, opt-in via SCUT_MAIL_ATTACH_DIR) ────────────────────────────
cat > "$eml/05-umlaut-anhang.eml" <<'EOF'
From: partner@example.com
To: team@example.com
Subject: [acme] Datei mit Umlaut-Namen
Message-ID: <a5@example.com>
Date: Fri, 04 Jul 2026 10:04:00 +0200
MIME-Version: 1.0
Content-Type: multipart/mixed; boundary="B"

--B
Content-Type: text/plain

Anbei die Datei.
--B
Content-Type: image/png
Content-Disposition: attachment; filename*=UTF-8''b%C3%B6se%20datei%3F.png

FAKEPNG
--B--
EOF
cat > "$eml/06-kollision-traversal.eml" <<'EOF'
From: partner@example.com
To: team@example.com
Subject: [acme] drei Anhänge
Message-ID: <a6@example.com>
Date: Fri, 04 Jul 2026 10:05:00 +0200
MIME-Version: 1.0
Content-Type: multipart/mixed; boundary="B"

--B
Content-Type: text/plain

Anbei.
--B
Content-Type: application/pdf
Content-Disposition: attachment; filename="doc.pdf"

AAA
--B
Content-Type: application/pdf
Content-Disposition: attachment; filename="doc.pdf"

BBB
--B
Content-Type: text/plain
Content-Disposition: attachment; filename="../../evil.txt"

EVIL
--B--
EOF
mdir="$tmp/mailfiles"
aout="$(SCUT_MAIL_EML_DIR="$eml" SCUT_MAIL_ATTACH_DIR="$mdir" bash "$BIN")"
ok "Duo: Volltext-File geschrieben" test -s "$mdir/eml004-body.txt"
ok "Duo: Volltext enthält Header+Body" grep -q "Subject: Unterlagen" "$mdir/eml004-body.txt"
ok "Anhang gespeichert (eml004-doc.pdf)" test -s "$mdir/eml004-doc.pdf"
t "Zeile referenziert Volltext+Anhang" "1" \
  "$(printf '%s\n' "$aout" | sed -n 4p | grep -c 'Volltext: eml004-body.txt · Anhänge: eml004-doc.pdf')"
ok "Umlaut-Name ASCII-sanitiert" test -s "$mdir/eml005-bose_datei_.png"
t "sanitierter Name in der Zeile" "1" "$(printf '%s\n' "$aout" | sed -n 5p | grep -c 'eml005-bose_datei_.png')"

# Kollisions-Dedup (Review-A1): zwei gleichnamige Anhänge einer Mail → -2-Suffix, beide Inhalte da
ok "Kollision: erste Datei" test -s "$mdir/eml006-doc.pdf"
ok "Kollision: zweite Datei mit Suffix" test -s "$mdir/eml006-doc-2.pdf"
t "Kollision: Inhalte verschieden" "1" "$(cmp -s "$mdir/eml006-doc.pdf" "$mdir/eml006-doc-2.pdf"; [ $? -ne 0 ] && echo 1 || echo 0)"

# Traversal-Assert (Review-A3): "../../evil.txt" landet sanitiert IN ATTACH_DIR, nichts außerhalb
ok "Traversal: Datei sanitiert im Zielordner" test -s "$mdir/eml006-evil.txt"
ok "Traversal: NICHTS außerhalb geschrieben" test ! -e "$tmp/evil.txt"
ok "Traversal: auch nicht eine Ebene höher" test ! -e "$(dirname "$tmp")/evil.txt"

# Fail-Degradation (Review-A2/Test-Gate-Fund): unbeschreibbarer ATTACH_DIR versenkt NICHT den Batch
rodir="$tmp/ro"; mkdir -p "$rodir"; chmod 555 "$rodir"
fout="$(SCUT_MAIL_EML_DIR="$eml" SCUT_MAIL_ATTACH_DIR="$rodir" bash "$BIN" 2>/dev/null)"; frc=$?
chmod 755 "$rodir"
t "Fail-loud: Batch überlebt (exit 0)" "0" "$frc"
t "Fail-loud: alle Events trotzdem emittiert" "6" "$(printf '%s\n' "$fout" | wc -l | tr -d ' ')"
t "Fail-loud: Vermerk in der Zeile" "1" "$(printf '%s\n' "$fout" | sed -n 4p | grep -c 'Persistenz fehlgeschlagen')"

# H2/#50 STRICT-Modus: bei Persistenz-Fehler stoppt der Poll VOR dem Emit (Offset rückt nicht vor).
# Default (oben, Zeile 170) emittiert alle 6 trotz Fehler; STRICT bricht bei der ersten Fehl-Mail ab.
sout="$(chmod 555 "$rodir"; SCUT_MAIL_EML_DIR="$eml" SCUT_MAIL_ATTACH_DIR="$rodir" SCUT_MAIL_ATTACH_STRICT=1 bash "$BIN" 2>/dev/null; chmod 755 "$rodir")"
serr="$(chmod 555 "$rodir"; SCUT_MAIL_EML_DIR="$eml" SCUT_MAIL_ATTACH_DIR="$rodir" SCUT_MAIL_ATTACH_STRICT=1 bash "$BIN" 2>&1 >/dev/null; chmod 755 "$rodir")"
t "STRICT: Poll stoppt bei erster Fehl-Mail (0 emittiert)" "0" "$(printf '%s' "$sout" | grep -c .)"
t "STRICT: exit 0 (kein Crash, laut in stderr)" "0" "$(chmod 555 "$rodir"; SCUT_MAIL_EML_DIR="$eml" SCUT_MAIL_ATTACH_DIR="$rodir" SCUT_MAIL_ATTACH_STRICT=1 bash "$BIN" >/dev/null 2>&1; echo $?; chmod 755 "$rodir")"
t "STRICT: stderr nennt Offset-nicht-vorgerückt" "1" "$(printf '%s\n' "$serr" | grep -c 'STRICT.*Offset NICHT vorgerückt')"
# STRICT ohne Fehler (beschreibbarer Dir) verhält sich wie Default: alle emittiert
sokdir="$tmp/strictok"; sok="$(SCUT_MAIL_EML_DIR="$eml" SCUT_MAIL_ATTACH_DIR="$sokdir" SCUT_MAIL_ATTACH_STRICT=1 bash "$BIN" 2>/dev/null)"
t "STRICT ohne Fehler: alle 6 emittiert" "6" "$(printf '%s\n' "$sok" | wc -l | tr -d ' ')"

# Size-Cap: zu großer Anhang wird übersprungen + vermerkt, Datei NICHT geschrieben
cdir="$tmp/capfiles"
cout="$(SCUT_MAIL_EML_DIR="$eml" SCUT_MAIL_ATTACH_DIR="$cdir" SCUT_MAIL_ATTACH_MAX=4 bash "$BIN")"
t "Cap: Skip-Vermerk in der Zeile" "1" "$(printf '%s\n' "$cout" | sed -n 4p | grep -c 'übersprungen (>4B, im Postfach)')"
ok "Cap: Anhang-Datei nicht geschrieben" test ! -e "$cdir/eml004-doc.pdf"
ok "Cap: Volltext trotzdem da" test -s "$cdir/eml004-body.txt"

# Default (ohne ATTACH_DIR) bleibt v1: nur zählen — Regression siehe Checks oben (Zeile 4)

# IMAP-Modus ohne Creds → exit 1 (klarer Fehler, kein Hänger)
t "ohne Creds: exit 1" "1" \
  "$(SCUT_MAIL_EML_DIR= SCUT_MAIL_HOST= SCUT_MAIL_USER= SCUT_MAIL_PASS= SCUT_SECRETS_DIR="$tmp/leer" \
     SCUT_MAIL_ONESHOT=1 bash "$BIN" >/dev/null 2>&1; echo $?)"

# Ende-zu-Ende-Smoke: Adapter → Router (Dry-Run) triagiert gerichtet + ungerichtet
route="$(SCUT_MAIL_EML_DIR="$eml" bash "$BIN" | SCUT_ROUTER_DRYRUN=1 DEV_TEAM_REGISTRY="$tmp/keine.json" CONTEXT_UID=ctx bash "$ROUTER" 2>/dev/null)"
t "Router-Smoke: gerichtet → inbox[acme]" "5" "$(printf '%s\n' "$route" | grep -c 'inbox\[acme\]')"
t "Router-Smoke: ungerichtet → review-queue" "1" "$(printf '%s\n' "$route" | grep -c 'review-queue\[ctx\]')"

echo "email_channel_spec: $pass passed, $fail failed"
[ "$fail" = 0 ]
