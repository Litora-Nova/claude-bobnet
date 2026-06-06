#!/usr/bin/env bash
# tests/dashboard_beats_spec.sh — Black-Box-Spec gegen den geteilten Heartbeat-
# Zeilen-Parser dashboard/server/utils/beats.mjs (Pre-main-Fix, Commit b8e3cf0).
#
# Was der Fix garantiert (Order PO 2026-06-06, Live-Symptom: alte datumslose
# 14:36-Beats schlugen heutige in der Flotten-Übersicht; + Review-Gate-Zonen-Skew):
#   (a) ISO-Stamps "YYYY-MM-DD HH:MM" -> epoch über die TEAM-Zeitzone
#       (env DEV_TEAM_TZ, Default Europe/Berlin), DST-fest via Intl — NICHT Date.UTC.
#   (b) datumslose Alt-Zeilen "HH:MM": NUR die LETZTE Zeile einer Datei bekommt den
#       mtime-Anker; alle früheren sind stale (epoch 0). Unparsebares ebenso stale.
#   (c) parseTail(lines, mtimeMs, {tz, limit}) kapselt die isLast-Regel.
#
# PO-Order wörtlich: „gestern-14:36 darf heute-10:36 nicht schlagen" (Check 4).
# Aufruf der PUREN functions direkt via node --input-type=module gegen die .mjs
# (wie tests/dashboard_activity_spec.sh) — zeitunabhängig, keine Wanduhr.
set -uo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/_helper.sh"

MJS="$ENGINE_ROOT/dashboard/server/utils/beats.mjs"

it "beats.mjs existiert (Fix b8e3cf0 eingespielt)"
ok test -f "$MJS"

# n "<expr>" — wertet einen JS-Ausdruck gegen die importierten functions aus.
# Importiert alles, was die Spec braucht; MTIME = fixer Anker (UTC ms), tz-frei.
n() { node --input-type=module -e "import {zonedEpoch, parseBeatLine, parseTail, DEFAULT_TZ, teamTz} from 'file://$MJS'; const MTIME=1780740000000; console.log($1)"; }

# ── zonedEpoch: Team-Zeitzone statt Date.UTC ─────────────────────────────────
it "1. Sommer-Offset (CEST=UTC+2): 2026-06-06 12:00 Berlin == 10:00 UTC"
eq "$(n "zonedEpoch(2026,6,6,12,0,'Europe/Berlin')")" "$(n "Date.UTC(2026,5,6,10,0)")"

it "2. Winter-Offset (CET=UTC+1): 2026-01-15 12:00 Berlin == 11:00 UTC"
eq "$(n "zonedEpoch(2026,1,15,12,0,'Europe/Berlin')")" "$(n "Date.UTC(2026,0,15,11,0)")"

it "Default-TZ ist Europe/Berlin (zonedEpoch ohne tz == mit Berlin)"
eq "$(n "zonedEpoch(2026,6,6,12,0)")" "$(n "zonedEpoch(2026,6,6,12,0,'Europe/Berlin')")"

it "DEFAULT_TZ-Konstante == Europe/Berlin, teamTz({}) fällt darauf"
eq "$(n "DEFAULT_TZ + '/' + teamTz({})")" "Europe/Berlin/Europe/Berlin"

it "teamTz liest env DEV_TEAM_TZ"
eq "$(n "teamTz({DEV_TEAM_TZ:'UTC'})")" "UTC"

# ── 3. DST-Kante: kein absurder Stunden-Sprung ───────────────────────────────
# Frühjahrs-Umstellung DE: 29.03.2026, 02:00 -> 03:00 (CET+1 -> CEST+2).
it "3a. DST-Kante: 03:30 NACH dem Sprung == 01:30 UTC (CEST+2, plausibel)"
eq "$(n "zonedEpoch(2026,3,29,3,30,'Europe/Berlin')")" "$(n "Date.UTC(2026,2,29,1,30)")"

it "3b. DST-Kante: 01:30 VOR dem Sprung == 00:30 UTC (CET+1)"
eq "$(n "zonedEpoch(2026,3,29,1,30,'Europe/Berlin')")" "$(n "Date.UTC(2026,2,29,0,30)")"

it "3c. DST-Kante: Wand-Delta 01:30->03:30 = nur 1 reale Stunde (Lücke geschluckt, kein Absturz)"
eq "$(n "zonedEpoch(2026,3,29,3,30,'Europe/Berlin') - zonedEpoch(2026,3,29,1,30,'Europe/Berlin')")" "3600000"

it "3d. Herbst-Kante 25.10.2026 03:30 == 02:30 UTC (zurück auf CET+1)"
eq "$(n "zonedEpoch(2026,10,25,3,30,'Europe/Berlin')")" "$(n "Date.UTC(2026,9,25,2,30)")"

# ── 4. DAS SYMPTOM (PO-Order wörtlich) ───────────────────────────────────────
# Alte datumslose "14:36" (NICHT letzte Zeile) darf heutige ISO "10:36" nicht schlagen.
it "4a. alte datumslose 14:36 (nicht-letzte) ist STALE (epoch 0)"
eq "$(n "JSON.stringify([parseBeatLine('14:36 | busy | gestern', MTIME, {tz:'Europe/Berlin', isLast:false}).epoch, parseBeatLine('14:36 | busy | gestern', MTIME, {tz:'Europe/Berlin', isLast:false}).stale])")" "[0,true]"

it "4b. heutige ISO 10:36 hat den GRÖSSEREN epoch — schlägt die alte 14:36 (Symptom behoben)"
eq "$(n "(()=>{const o=parseBeatLine('14:36 | busy | g', MTIME, {tz:'Europe/Berlin', isLast:false}); const i=parseBeatLine('2026-06-06 10:36 | busy | h', MTIME, {tz:'Europe/Berlin', isLast:true}); return i.epoch > o.epoch})()")" "true"

it "4c. die heutige ISO-Zeile selbst ist nicht stale und hat epoch>0"
eq "$(n "(()=>{const i=parseBeatLine('2026-06-06 10:36 | busy | h', MTIME, {tz:'Europe/Berlin', isLast:true}); return JSON.stringify([i.epoch>0, i.stale])})()")" "[true,false]"

# ── 5. letzte datumslose Zeile -> mtime-Anker, nicht stale ───────────────────
it "5. letzte datumslose 14:36 -> epoch == fileMtimeMs (mtime-Anker), nicht stale"
eq "$(n "(()=>{const l=parseBeatLine('14:36 | busy | x', MTIME, {isLast:true}); return JSON.stringify([l.epoch===MTIME, l.stale])})()")" "[true,false]"

it "5b. HH:MM bleibt Anzeige-time, date leer (Tag unbekannt)"
eq "$(n "(()=>{const l=parseBeatLine('14:36 | busy | x', MTIME, {isLast:true}); return l.time + '|' + l.date})()")" "14:36|"

# ── 6. tz-Override via opts.tz greift ────────────────────────────────────────
it "6. opts.tz=UTC vs Europe/Berlin ergibt 2h Differenz (Sommer-Stamp)"
eq "$(n "parseBeatLine('2026-06-06 12:00 | busy | x', MTIME, {tz:'UTC', isLast:true}).epoch - parseBeatLine('2026-06-06 12:00 | busy | x', MTIME, {tz:'Europe/Berlin', isLast:true}).epoch")" "7200000"

it "6b. opts.tz=UTC: ISO 12:00 == 12:00 UTC (kein Offset)"
eq "$(n "parseBeatLine('2026-06-06 12:00 | busy | x', MTIME, {tz:'UTC', isLast:true}).epoch")" "$(n "Date.UTC(2026,5,6,12,0)")"

# ── 7. Unparsebare Zeile -> stale ────────────────────────────────────────────
it "7. unparsebare Zeile (kein gültiger Stempel) -> stale, epoch 0 (auch als letzte)"
eq "$(n "(()=>{const j=parseBeatLine('Tagebucheintrag ohne Stempel', MTIME, {isLast:true}); return JSON.stringify([j.stale, j.epoch])})()")" "[true,0]"

it "7b. leere/strukturlose Zeile -> stale"
eq "$(n "parseBeatLine('   ', MTIME, {isLast:true}).stale")" "true"

# ── 8. parseTail: limit greift + isLast nur fürs letzte Element ──────────────
# Datei-Reihenfolge (NICHT reversed). Mix aus datumslosen + ISO-Zeilen.
it "8a. parseTail limit=2 -> genau 2 Ergebnisse (letzte N Zeilen)"
eq "$(n "parseTail(['10:00 | busy | a','11:00 | busy | b','2026-06-06 12:00 | busy | c'], MTIME, {tz:'Europe/Berlin', limit:2}).length")" "2"

it "8b. parseTail: NUR das letzte Element gilt als isLast (datumslose Vorgänger stale)"
eq "$(n "(()=>{const t=parseTail(['10:00 | busy | a','11:00 | busy | b'], MTIME, {limit:2}); return JSON.stringify([t[0].stale, t[1].stale, t[1].epoch===MTIME])})()")" "[true,false,true]"

it "8c. parseTail ohne limit -> alle Zeilen, nur die letzte datumslose bekommt mtime"
eq "$(n "(()=>{const t=parseTail(['10:00 | busy | a','11:00 | busy | b','12:00 | busy | c'], MTIME); return JSON.stringify([t.length, t[0].stale, t[1].stale, t[2].epoch===MTIME])})()")" "[3,true,true,true]"

it "8d. parseTail: ISO-Zeile als letztes Element trägt zonen-korrekten epoch (nicht mtime)"
eq "$(n "parseTail(['11:00 | busy | a','2026-06-06 12:00 | busy | b'], MTIME, {tz:'Europe/Berlin'})[1].epoch")" "$(n "Date.UTC(2026,5,6,10,0)")"

# ── Zusatz: Struktur des Rückgabe-Objekts (eigenes Urteil) ───────────────────
it "+a. parseBeatLine zerlegt status + msg (auch msg mit Pipe bleibt erhalten)"
eq "$(n "(()=>{const b=parseBeatLine('2026-06-06 12:00 | busy | hallo | welt', MTIME, {isLast:true}); return b.status + '::' + b.msg})()")" "busy::hallo | welt"

it "+b. ISO mit T-Trenner ('YYYY-MM-DDTHH:MM') wird ebenso geparst"
eq "$(n "parseBeatLine('2026-06-06T12:00 | busy | x', MTIME, {tz:'Europe/Berlin', isLast:true}).epoch")" "$(n "Date.UTC(2026,5,6,10,0)")"

it "+c. ISO-epoch ist isLast-UNabhängig (Datum trägt sich selbst, mtime irrelevant)"
eq "$(n "parseBeatLine('2026-06-06 12:00 | busy | x', MTIME, {tz:'Europe/Berlin', isLast:false}).epoch")" "$(n "parseBeatLine('2026-06-06 12:00 | busy | x', MTIME, {tz:'Europe/Berlin', isLast:true}).epoch")"

summary
