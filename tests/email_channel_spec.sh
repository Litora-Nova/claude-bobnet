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
# L9/#51: ENOTDIR statt chmod 555 — ein Pfad UNTER einer regulären Datei kann NIE zum
# Verzeichnis werden, schlägt also strukturell fehl, auch wenn die Suite als root läuft
# (chmod 555 wäre das nicht — root ignoriert Dateimodus-Bits).
roblock="$tmp/ro-blocker"; touch "$roblock"
rodir="$roblock/sub"
fout="$(SCUT_MAIL_EML_DIR="$eml" SCUT_MAIL_ATTACH_DIR="$rodir" bash "$BIN" 2>/dev/null)"; frc=$?
t "Fail-loud: Batch überlebt (exit 0)" "0" "$frc"
t "Fail-loud: alle Events trotzdem emittiert" "6" "$(printf '%s\n' "$fout" | wc -l | tr -d ' ')"
t "Fail-loud: Vermerk in der Zeile" "1" "$(printf '%s\n' "$fout" | sed -n 4p | grep -c 'Persistenz fehlgeschlagen')"
# N1/#51: bei 0 Anhängen (Zeile 2 = 02-ungerichtet.eml) darf der Vermerk nicht "0 Anhänge" sagen
t "N1: 0-Anhang-Mail bekommt eigene Formulierung" "1" \
  "$(printf '%s\n' "$fout" | sed -n 2p | grep -c 'Mailtext nicht abgelegt')"
t "N1: 0-Anhang-Mail NICHT die Anhang-Zähl-Formulierung" "0" \
  "$(printf '%s\n' "$fout" | sed -n 2p | grep -c '0 Anhang')"

# H2/#50 STRICT-Modus: bei Persistenz-Fehler stoppt der Poll VOR dem Emit (Offset rückt nicht vor).
# Default (oben) emittiert alle 6 trotz Fehler; STRICT bricht bei der ersten Fehl-Mail ab.
sout="$(SCUT_MAIL_EML_DIR="$eml" SCUT_MAIL_ATTACH_DIR="$rodir" SCUT_MAIL_ATTACH_STRICT=1 bash "$BIN" 2>/dev/null)"
serr="$(SCUT_MAIL_EML_DIR="$eml" SCUT_MAIL_ATTACH_DIR="$rodir" SCUT_MAIL_ATTACH_STRICT=1 bash "$BIN" 2>&1 >/dev/null)"
t "STRICT: Poll stoppt bei erster Fehl-Mail (0 emittiert)" "0" "$(printf '%s' "$sout" | grep -c .)"
t "STRICT: exit 0 (kein Crash, laut in stderr)" "0" "$(SCUT_MAIL_EML_DIR="$eml" SCUT_MAIL_ATTACH_DIR="$rodir" SCUT_MAIL_ATTACH_STRICT=1 bash "$BIN" >/dev/null 2>&1; echo $?)"
t "STRICT: stderr nennt Offset-nicht-vorgerückt" "1" "$(printf '%s\n' "$serr" | grep -c 'STRICT.*Offset NICHT vorgerückt')"
# STRICT ohne Fehler (beschreibbarer Dir) verhält sich wie Default: alle emittiert
sokdir="$tmp/strictok"; sok="$(SCUT_MAIL_EML_DIR="$eml" SCUT_MAIL_ATTACH_DIR="$sokdir" SCUT_MAIL_ATTACH_STRICT=1 bash "$BIN" 2>/dev/null)"
t "STRICT ohne Fehler: alle 6 emittiert" "6" "$(printf '%s\n' "$sok" | wc -l | tr -d ' ')"

# ── L9/#51 Marvins Test-Seam: den IMAP-Offset selbst prüfen (nicht nur die stderr-Meldung) ──
# SCUT_MAIL_EML_OFFSET_TEST=1 lässt den EML-Testmodus einen echten (synthetischen) Offset-
# Token schreiben, damit sich "rückt vor" (Default) vs. "hält" (STRICT) am Offset-File selbst
# beobachten lässt — sonst bleibt der EML-Testmodus offset-los wie bisher (kein Regressions-Risiko).
offset_default="$tmp/offset-default"
SCUT_MAIL_EML_DIR="$eml" SCUT_MAIL_EML_OFFSET_TEST=1 SCUT_MAIL_ATTACH_DIR="$rodir" \
  SCUT_MAIL_OFFSET_FILE="$offset_default" bash "$BIN" >/dev/null 2>&1
t "L9: Default (best-effort) rückt den Offset trotz Fehler vor" "1" "$([ -s "$offset_default" ] && echo 1 || echo 0)"
ok "L9: Offset zeigt auf die letzte verarbeitete Mail" grep -qx 'emltest:006' "$offset_default"
offset_strict="$tmp/offset-strict"
SCUT_MAIL_EML_DIR="$eml" SCUT_MAIL_EML_OFFSET_TEST=1 SCUT_MAIL_ATTACH_DIR="$rodir" \
  SCUT_MAIL_ATTACH_STRICT=1 SCUT_MAIL_OFFSET_FILE="$offset_strict" bash "$BIN" >/dev/null 2>&1
t "L9: STRICT hält den Offset an (No-Loss, keine Datei geschrieben)" "0" "$([ -e "$offset_strict" ] && echo 1 || echo 0)"

# Size-Cap: zu großer Anhang wird übersprungen + vermerkt, Datei NICHT geschrieben
cdir="$tmp/capfiles"
cout="$(SCUT_MAIL_EML_DIR="$eml" SCUT_MAIL_ATTACH_DIR="$cdir" SCUT_MAIL_ATTACH_MAX=4 bash "$BIN")"
t "Cap: Skip-Vermerk in der Zeile" "1" "$(printf '%s\n' "$cout" | sed -n 4p | grep -c 'übersprungen (>4B, im Postfach)')"
ok "Cap: Anhang-Datei nicht geschrieben" test ! -e "$cdir/eml004-doc.pdf"
ok "Cap: Volltext trotzdem da" test -s "$cdir/eml004-body.txt"

# ── M6/#51: Caps gegen unbounded IO — Body-Cap · Anzahl-Cap · Aggregat-Byte-Cap ─────────────
eml_m6_body="$tmp/eml_m6_body"; mkdir -p "$eml_m6_body"
cat > "$eml_m6_body/01.eml" <<EOF
From: partner@example.com
To: team@example.com
Subject: [acme] langer body
Message-ID: <m6-body@example.com>
Date: Fri, 04 Jul 2026 11:00:00 +0200

$(python3 -c "print('ä'*60, end='')")
EOF
bodydir="$tmp/m6-body"
bout="$(SCUT_MAIL_EML_DIR="$eml_m6_body" SCUT_MAIL_ATTACH_DIR="$bodydir" SCUT_MAIL_BODY_MAX=51 bash "$BIN")"
t "M6 Body-Cap: Vermerk in der Zeile" "1" "$(printf '%s\n' "$bout" | grep -c 'gekürzt, > 51B')"
ok "M6 Body-Cap: body.txt bleibt unter dem Cap (Header+51B)" test "$(wc -c < "$bodydir/eml001-body.txt")" -lt 250
ok "M6 Body-Cap: body.txt ist gültiges UTF-8 (Schnitt an Zeichengrenze)" python3 -c "open('$bodydir/eml001-body.txt', encoding='utf-8').read()"
ok "M6 Body-Cap: 25 'ä' erhalten (50 von 51 Bytes, Rest verworfen)" grep -q "$(python3 -c "print('ä'*25, end='')")" "$bodydir/eml001-body.txt"

eml_m6_count="$tmp/eml_m6_count"; mkdir -p "$eml_m6_count"
cat > "$eml_m6_count/01.eml" <<'EOF'
From: partner@example.com
To: team@example.com
Subject: [acme] drei anhaenge count
Message-ID: <m6-count@example.com>
Date: Fri, 04 Jul 2026 11:01:00 +0200
MIME-Version: 1.0
Content-Type: multipart/mixed; boundary="B"

--B
Content-Type: text/plain

Drei Anhaenge, Count-Cap testen.
--B
Content-Type: application/octet-stream
Content-Disposition: attachment; filename="a.bin"

AAA
--B
Content-Type: application/octet-stream
Content-Disposition: attachment; filename="b.bin"

BBB
--B
Content-Type: application/octet-stream
Content-Disposition: attachment; filename="c.bin"

CCC
--B--
EOF
countdir="$tmp/m6-count"
ccout="$(SCUT_MAIL_EML_DIR="$eml_m6_count" SCUT_MAIL_ATTACH_DIR="$countdir" SCUT_MAIL_ATTACH_MAX_COUNT=2 bash "$BIN")"
t "M6 Count-Cap: nur 2 von 3 Anhängen gespeichert" "1" "$(printf '%s\n' "$ccout" | grep -c 'übersprungen (>2 Anhänge/Mail, im Postfach)')"
ok "M6 Count-Cap: erster Anhang da" test -s "$countdir/eml001-a.bin"
ok "M6 Count-Cap: zweiter Anhang da" test -s "$countdir/eml001-b.bin"
ok "M6 Count-Cap: dritter NICHT gespeichert" test ! -e "$countdir/eml001-c.bin"

eml_m6_total="$tmp/eml_m6_total"; mkdir -p "$eml_m6_total"
cat > "$eml_m6_total/01.eml" <<EOF
From: partner@example.com
To: team@example.com
Subject: [acme] zwei anhaenge total
Message-ID: <m6-total@example.com>
Date: Fri, 04 Jul 2026 11:02:00 +0200
MIME-Version: 1.0
Content-Type: multipart/mixed; boundary="B"

--B
Content-Type: text/plain

Zwei Anhaenge, Total-Cap testen.
--B
Content-Type: application/octet-stream
Content-Disposition: attachment; filename="big1.bin"

$(python3 -c "print('A'*40, end='')")
--B
Content-Type: application/octet-stream
Content-Disposition: attachment; filename="big2.bin"

$(python3 -c "print('B'*40, end='')")
--B--
EOF
totaldir="$tmp/m6-total"
tcout="$(SCUT_MAIL_EML_DIR="$eml_m6_total" SCUT_MAIL_ATTACH_DIR="$totaldir" SCUT_MAIL_ATTACH_MAX_TOTAL=50 bash "$BIN")"
t "M6 Total-Cap: zweiter Anhang übersprungen (Summe >50B)" "1" "$(printf '%s\n' "$tcout" | grep -c 'übersprungen (Summe >50B, im Postfach)')"
ok "M6 Total-Cap: erster Anhang (40B) unter dem Cap gespeichert" test -s "$totaldir/eml001-big1.bin"
ok "M6 Total-Cap: zweiter Anhang NICHT gespeichert (40+40 > 50)" test ! -e "$totaldir/eml001-big2.bin"

# ── R1(3)/#52: Größen-Vorprüfung bei misdeklariertem/exotischem Transfer-Encoding ───────────
# estimate_encoded_bytes() behandelt jedes NICHT-base64-CTE als "rohe Länge = sichere obere
# Schranke" (kein Decode nötig, um zu schätzen). Kein Bug gefunden — dieser Test nagelt das
# Verhalten fest: ein Anhang mit (falsch deklariertem) quoted-printable-CTE bleibt unter dem
# Cap korrekt erfasst UND crasht beim echten Decode nicht, auch wenn der Inhalt kein gültiges
# quoted-printable ist.
eml_cte="$tmp/eml_cte"; mkdir -p "$eml_cte"
cat > "$eml_cte/01-cte-edge.eml" <<'EOF'
From: partner@example.com
To: team@example.com
Subject: [acme] CTE-Edge
Message-ID: <cte1@example.com>
Date: Fri, 05 Jul 2026 09:03:00 +0200
MIME-Version: 1.0
Content-Type: multipart/mixed; boundary="B"

--B
Content-Type: text/plain

CTE-Edge-Test.
--B
Content-Type: application/octet-stream
Content-Disposition: attachment; filename="mystery.bin"
Content-Transfer-Encoding: quoted-printable

payload=3D=0A=0Amehr=3D=3D=3D=3D=3D=3D=3D=3D=3D=3D
--B--
EOF
ctedir="$tmp/cte-cap"
cteout="$(SCUT_MAIL_EML_DIR="$eml_cte" SCUT_MAIL_ATTACH_DIR="$ctedir" SCUT_MAIL_ATTACH_MAX=4 bash "$BIN")"; cterc=$?
t "CTE-Edge + Cap: kein Crash (exit 0)" "0" "$cterc"
t "CTE-Edge: Anhang wegen Cap übersprungen (Vorprüfung greift trotz CTE)" "1" \
  "$(printf '%s\n' "$cteout" | grep -c 'übersprungen (>4B, im Postfach)')"
ok "CTE-Edge: Anhang-Datei NICHT geschrieben" test ! -e "$ctedir/eml001-mystery.bin"
ok "CTE-Edge: Volltext trotzdem da (Mail zugestellt)" test -s "$ctedir/eml001-body.txt"
ctedir2="$tmp/cte-nocap"
cteout2="$(SCUT_MAIL_EML_DIR="$eml_cte" SCUT_MAIL_ATTACH_DIR="$ctedir2" bash "$BIN")"; cterc2=$?
t "CTE-Edge ohne Cap: kein Crash (exit 0)" "0" "$cterc2"
ok "CTE-Edge ohne Cap: Anhang trotzdem decodiert+gespeichert" test -s "$ctedir2/eml001-mystery.bin"

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
