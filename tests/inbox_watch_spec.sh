#!/usr/bin/env bash
# tests/inbox_watch_spec.sh — scripts/inbox-watch.sh (Watcher-Entscheidungslogik, Dry-Run ohne mux).
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN="$HERE/../scripts/inbox-watch.sh"
pass=0; fail=0
t(){ local d="$1" exp="$2" got="$3"; if [ "$got" = "$exp" ]; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL: $d — erwartet '$exp', bekam '$got'"; fi; }
ok(){ local d="$1"; shift; if "$@" >/dev/null 2>&1; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL: $d"; fi; }

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
ok "bash -n sauber" bash -n "$BIN"

mkdir -p "$tmp/alpha/_dev_team/standup" "$tmp/beta/_dev_team/standup" "$tmp/state"
cat > "$tmp/registry.json" <<JSON
{ "version":1, "projects":[
  {"uid":"alpha","name":"alpha","path":"$tmp/alpha","standup":"$tmp/alpha/_dev_team/standup","status":"active"},
  {"uid":"beta","name":"beta","path":"$tmp/beta","standup":"$tmp/beta/_dev_team/standup","status":"active"},
  {"uid":"leer","name":"leer","path":"$tmp/leer","standup":"$tmp/leer","status":"active"},
  {"uid":"delta","name":"delta","path":"$tmp/delta","standup":"$tmp/delta/_dev_team/standup","status":"active"}
]}
JSON
printf 'export TEAM_LEAD="Zed"\nexport MUX_SESSION="alpha_sess"\n' > "$tmp/alpha/_dev_team/dev-team.env"
printf 'export TEAM_LEAD="Yui"\n' > "$tmp/beta/_dev_team/dev-team.env"
# "delta" bleibt bis zum Alt-Format-Test (f) unmaterialisiert (keine _inbox.md -> harmlos "skip").

A="$tmp/alpha/_dev_team/standup"; B="$tmp/beta/_dev_team/standup"
echo "x | @Zed | hallo" > "$A/_inbox.md"
echo "y | @Yui | hallo" > "$B/_inbox.md"
now(){ date '+%Y-%m-%d %H:%M'; }
MAXN=3
run(){ DEV_TEAM_REGISTRY="$tmp/registry.json" INBOX_WATCH_STATE="$tmp/state" INBOX_WATCH_DRYRUN=1 INBOX_WATCH_MAX_NUDGE="$MAXN" bash "$BIN" 2>/dev/null; }

# Lauf 1: alpha-Lead idle → NUDGE #1 (State bleibt PENDING, NICHT sofort finalisiert — Kern von
# #48: der mux_send-rc ist nicht vertrauenswürdig, s. Kopf von inbox-watch.sh) · beta ohne
# MUX_SESSION → kein Weckweg, kein Alert-Cmd konfiguriert → VERSCHLUCKT (laut geloggt, nicht
# still wie vor #48) · leer ohne Inbox → skip
echo "$(now) | idle | warte" > "$A/Zed.log"
echo "$(now) | idle | warte" > "$B/Yui.log"
out="$(run)"; rc=$?
t "exit 0" "0" "$rc"
t "neu + idle → NUDGE #1" "1" "$(printf '%s\n' "$out" | grep -c 'alpha: NUDGE #1 → alpha_sess')"
t "ohne MUX_SESSION, kein Alert-Cmd → VERSCHLUCKT" "1" "$(printf '%s\n' "$out" | grep -c 'beta: NEU.*kein Weckweg.*VERSCHLUCKT')"
t "ohne _inbox.md → skip" "1" "$(printf '%s\n' "$out" | grep -c 'leer: keine _inbox.md')"
t "State nach Nudge = PENDING, nicht final" "PENDING" "$(cut -d' ' -f1 "$tmp/state/alpha.state")"

# (a) Nudge finalisiert NICHT: ohne neuen Heartbeat bleibt die Signatur offen → Re-Nudge #2,
# nicht "ok (unverändert)".
out="$(run)"
t "(a) Nudge finalisiert nicht → Re-Nudge #2 statt ok" "1" "$(printf '%s\n' "$out" | grep -c 'alpha: NUDGE #2 → alpha_sess')"
t "(a) beta unverändert seit VERSCHLUCKT-Finalize → ok" "1" "$(printf '%s\n' "$out" | grep -c 'beta: ok')"

# (b) Heartbeat NACH dem Nudge finalisiert: neue Log-Zeile (kanonisch: Stand-up beginnt mit
# Heartbeat + Inbox lesen) verifiziert den ausstehenden Nudge, ohne dass sich die Inbox geändert
# hat → State wird auf die genudgte Signatur finalisiert, kein weiterer Nudge nötig.
echo "$(now) | idle | zurück" >> "$A/Zed.log"
out="$(run)"
t "(b) Heartbeat verifiziert den Nudge" "1" "$(printf '%s\n' "$out" | grep -c 'alpha: Nudge verifiziert')"
t "(b) keine weitere NUDGE-Zeile im selben Tick" "0" "$(printf '%s\n' "$out" | grep -c 'alpha: NUDGE')"
out="$(run)"
t "(b) danach: ok (unverändert)" "1" "$(printf '%s\n' "$out" | grep -c 'alpha: ok')"

# flock-Single-Instance-Guard (0.14.0-Gate, Riker-Fund): ein überlappender Zweitlauf wird
# sauber übersprungen (exit 0, kein State-Touch), damit ein Timer-/Cron-Overlap die
# "genau-einmal"-Eskalation nicht verletzen kann. Lock im Testprozess selbst halten (fd 8) —
# der Watcher öffnet dieselbe Lock-Datei in einem eigenen Prozess (fd 9) und muss non-blocking
# scheitern. Platziert an einem Punkt, an dem alpha/beta ruhig sind (beide "ok"), damit der
# zusätzliche Lauf nach der Freigabe keine späteren Zyklen verfälscht.
exec 8>"$tmp/state/.lock"
flock -n 8
out="$(run)"
t "flock-Guard: Zweitlauf wird übersprungen" "1" "$(printf '%s\n' "$out" | grep -c 'Lauf übersprungen')"
exec 8>&-
out="$(run)"
t "flock-Guard: nach Freigabe wieder normaler Lauf (alpha weiter ok)" "1" "$(printf '%s\n' "$out" | grep -c 'alpha: ok')"

# busy (frisch) → skip-busy, State bleibt offen → Wiederholungslauf meldet weiter NEU
echo "neuer eintrag" >> "$A/_inbox.md"
echo "$(now) | busy | arbeite" > "$A/Zed.log"
out="$(run)"
t "neu + busy → skip-busy" "1" "$(printf '%s\n' "$out" | grep -c 'alpha: NEU.*skip-busy')"
out="$(run)"
t "busy-Skip hält State offen (re-check)" "1" "$(printf '%s\n' "$out" | grep -c 'alpha: NEU.*skip-busy')"

# Lead wird done → jetzt NUDGE (neuer Zyklus, Versuchszähler bei 1)
echo "$(now) | done | fertig" > "$A/Zed.log"
out="$(run)"
t "done → NUDGE" "1" "$(printf '%s\n' "$out" | grep -c 'alpha: NUDGE #1')"

# stale-busy: alter busy-Heartbeat zählt als idle (Signatur wandert weiter → neuer Zyklus, der
# vorige unverifizierte Nudge bleibt bewusst hinter sich — s. Kopf-Doku Punkt 3)
echo "weiterer eintrag" >> "$A/_inbox.md"
echo "2020-01-01 00:00 | busy | uralt" > "$A/Zed.log"
out="$(run)"
t "stale-busy → NUDGE" "1" "$(printf '%s\n' "$out" | grep -c 'alpha: NUDGE')"

# blocked → skip-blocked (Mensch-Problem, nicht drauflegen)
echo "noch einer" >> "$A/_inbox.md"
echo "$(now) | blocked | warte auf PO" > "$A/Zed.log"
out="$(run)"
t "blocked → skip-blocked" "1" "$(printf '%s\n' "$out" | grep -c 'alpha: NEU.*skip-blocked')"

# kein Lead-Log (none) → nudgen (unbekannt behandeln wir wie idle)
rm "$A/Zed.log"
out="$(run)"
t "kein Heartbeat-Log → NUDGE" "1" "$(printf '%s\n' "$out" | grep -c 'alpha: NUDGE')"

# unparsbarer Timestamp + busy → stale behandeln → NUDGE (kaputter Heartbeat unterdrückt nicht)
echo "kaputter ts eintrag" >> "$A/_inbox.md"
echo "GARBAGE-TS | busy | haengt" > "$A/Zed.log"
out="$(run)"
t "Müll-Timestamp + busy → NUDGE (stale)" "1" "$(printf '%s\n' "$out" | grep -c 'alpha: NUDGE')"

# _inbox/-Dateidrop zählt als Neues (beta weiterhin ohne Alert-Cmd → VERSCHLUCKT)
mkdir -p "$B/_inbox"; echo bild > "$B/_inbox/foto.txt"
echo "$(now) | idle | warte" > "$B/Yui.log"
out="$(run)"
t "_inbox/-Drop → NEU (beta VERSCHLUCKT)" "1" "$(printf '%s\n' "$out" | grep -c 'beta: NEU.*VERSCHLUCKT')"

# Review-Queue-Eintrag zählt als Neues (ungerichtete Router-Mails dürfen nicht liegenbleiben)
echo "x | UNGERICHTET (via email, von kunde) | anfrage" >> "$B/_review-queue.md"
out="$(run)"
t "_review-queue.md → NEU (beta VERSCHLUCKT)" "1" "$(printf '%s\n' "$out" | grep -c 'beta: NEU.*VERSCHLUCKT')"

# (c) Re-Nudge zählt hoch + respektiert INBOX_WATCH_MAX_NUDGE: frischer Zyklus mit Limit 2 —
# #1, #2, dann erschöpft (KEIN #3), ohne Alert-Cmd laut VERSCHLUCKT.
MAXN=2
echo "frischer zyklus für re-nudge-test" >> "$A/_inbox.md"
echo "$(now) | idle | warte" > "$A/Zed.log"
out="$(run)"
t "(c) Re-Nudge #1" "1" "$(printf '%s\n' "$out" | grep -c 'alpha: NUDGE #1')"
out="$(run)"
t "(c) Re-Nudge #2 (Versuchszähler hoch)" "1" "$(printf '%s\n' "$out" | grep -c 'alpha: NUDGE #2')"
out="$(run)"
t "(c) Limit respektiert: kein #3" "0" "$(printf '%s\n' "$out" | grep -c 'alpha: NUDGE #3')"
t "(c) erschöpft ohne Alert-Cmd → VERSCHLUCKT" "1" "$(printf '%s\n' "$out" | grep -c 'alpha:.*erschöpft.*VERSCHLUCKT')"

# (d) Alert-Cmd feuert GENAU EINMAL bei Erschöpfung.
alerts="$tmp/alerts.log"
cat > "$tmp/alert.sh" <<SH
#!/usr/bin/env bash
echo "ALERT uid=\$1 lead=\$2 standup=\$3" >> "$alerts"
SH
chmod +x "$tmp/alert.sh"
printf 'export INBOX_WATCH_ALERT_CMD="%s"\n' "$tmp/alert.sh" >> "$tmp/alpha/_dev_team/dev-team.env"
echo "neuer zyklus mit alert-cmd" >> "$A/_inbox.md"
echo "$(now) | idle | warte" > "$A/Zed.log"
run >/dev/null   # #1
run >/dev/null   # #2 (MAXN=2)
out="$(run)"     # erschöpft → eskalieren
t "(d) erschöpft MIT Alert-Cmd → ESKALIERT" "1" "$(printf '%s\n' "$out" | grep -c 'alpha:.*erschöpft.*ESKALIERT')"
t "(d) Alert-Cmd genau einmal ausgeführt" "1" "$(wc -l < "$alerts" | tr -d ' ')"
out="$(run)"
t "(d) danach finalisiert → ok, kein zweiter Alert" "1" "$(printf '%s\n' "$out" | grep -c 'alpha: ok')"
t "(d) alerts.log wächst nicht weiter" "1" "$(wc -l < "$alerts" | tr -d ' ')"

# (e) report-only + Alert-Cmd feuert (kein MUX_SESSION → kein Re-Nudge-Zyklus, direkt eskaliert).
printf 'export INBOX_WATCH_ALERT_CMD="%s"\n' "$tmp/alert.sh" >> "$tmp/beta/_dev_team/dev-team.env"
echo "beta ohne weckweg, mit alert" >> "$B/_inbox.md"
out="$(run)"
t "(e) report-only MIT Alert-Cmd → ESKALIERT" "1" "$(printf '%s\n' "$out" | grep -c 'beta:.*kein Weckweg.*ESKALIERT')"
t "(e) Alert-Cmd feuert (zweiter Eintrag, uid=beta)" "1" "$(tail -n1 "$alerts" | grep -c 'uid=beta')"
t "(e) alerts.log jetzt 2 Zeilen (alpha + beta)" "2" "$(wc -l < "$alerts" | tr -d ' ')"
out="$(run)"
t "(e) danach finalisiert → ok, kein erneuter Alert" "1" "$(printf '%s\n' "$out" | grep -c 'beta: ok')"
t "(e) alerts.log wächst nicht weiter" "2" "$(wc -l < "$alerts" | tr -d ' ')"

# (f) Alt-Format-State kompatibel: eine vorbestehende nackte Signatur (Format vor #48) wird als
# "final" gelesen — kein Crash, keine Fehlinterpretation als PENDING; danach normale NEU-Erkennung.
mkdir -p "$tmp/delta/_dev_team/standup"
D="$tmp/delta/_dev_team/standup"
printf 'export TEAM_LEAD="Deb"\n' > "$tmp/delta/_dev_team/dev-team.env"
echo "delta eins" > "$D/_inbox.md"
dsig="$(wc -c < "$D/_inbox.md" | tr -d ' '):0:0"
printf '%s' "$dsig" > "$tmp/state/delta.state"
out="$(run)"
t "(f) Alt-Format-State unverändert → ok (kein Crash)" "1" "$(printf '%s\n' "$out" | grep -c 'delta: ok')"
echo "delta zwei" >> "$D/_inbox.md"
echo "$(now) | idle | warte" > "$D/Deb.log"
out="$(run)"
t "(f) Alt-Format-State, geänderte Signatur → normal als NEU erkannt" "1" "$(printf '%s\n' "$out" | grep -c 'delta: NEU')"

# (g) Alert-Fehlschlag getrennt zählen (0.14.0-Gate, Riker-Fund): ein ALERT_CMD, der selbst
# fehlschlägt (rc≠0), darf NICHT als "eskaliert" durchgehen — eigener Zähler + eigene
# Pro-Event-Zeile ("FEHLGESCHLAGEN", nicht "ESKALIERT").
cat > "$tmp/alert_fail.sh" <<'SH'
#!/usr/bin/env bash
exit 1
SH
chmod +x "$tmp/alert_fail.sh"
printf 'export TEAM_LEAD="Yui"\nexport INBOX_WATCH_ALERT_CMD="%s"\n' "$tmp/alert_fail.sh" > "$tmp/beta/_dev_team/dev-team.env"
echo "beta content mit fehlschlagendem alert-cmd" >> "$B/_inbox.md"
out="$(run)"
t "(g) Alert-Fehlschlag NICHT als ESKALIERT gezählt (Pro-Event-Zeile)" "0" "$(printf '%s\n' "$out" | grep -c 'beta:.*ESKALIERT')"
t "(g) Alert-Fehlschlag pro-Event-Zeile FEHLGESCHLAGEN" "1" "$(printf '%s\n' "$out" | grep -c 'beta:.*FEHLGESCHLAGEN')"
t "(g) Summary zählt Alert-Fehlschlag separat (nicht als eskaliert)" "1" "$(printf '%s\n' "$out" | grep -cE '── inbox-watch:.*0 eskaliert, 1 Alert-Fehlschlag')"

# (h) korrupte PENDING-Zeile konservativ (0.14.0-Gate, Marvin-Fund): fehlt ein Pflichtfeld
# (hier: sig), NICHT permissiv mit lines=0 "verifizieren" (das lässt fast jeden Heartbeat sofort
# als Zustellnachweis durchgehen) — stattdessen wie "kein State" behandeln, frischer Zyklus.
echo "$(now) | idle | schon einige zeilen im log" > "$A/Zed.log"
echo "$(now) | idle | noch mehr" >> "$A/Zed.log"
printf 'PENDING lines=0 attempts=1' > "$tmp/state/alpha.state"   # sig fehlt -> korrupt
echo "content für korrupten-pending-test" >> "$A/_inbox.md"
out="$(run)"
t "(h) korrupte PENDING-Zeile NICHT permissiv verifiziert" "0" "$(printf '%s\n' "$out" | grep -c 'alpha: Nudge verifiziert')"
t "(h) korrupte PENDING-Zeile als frischer Zyklus behandelt" "1" "$(printf '%s\n' "$out" | grep -c 'alpha: PENDING-State korrupt')"
t "(h) frischer Zyklus nudgt normal (#1)" "1" "$(printf '%s\n' "$out" | grep -c 'alpha: NUDGE #1')"

# (i)/(j) Boot-Pfad (INBOX_WATCH_BOOT=1): dev-team.env wird vor BOOT_CMD gesourct, weil
# BOOT_CMD in einer FRISCHEN Shell läuft (mux_spawn) — sonst wären $PROJECT_ROOT & Co. dort leer
# (gleicher Fußgänger + gleiche Kur wie bin/recycle f083dd3). Braucht einen echten Multiplexer
# (DRYRUN endet vor dem Boot-Zweig) — Backend fest auf tmux, das liefert auch headless
# zuverlässig zu (zellij ohne attached Client laut mux.sh-Doku nicht).
if command -v tmux >/dev/null 2>&1; then
  boot_marker="$tmp/boot_marker.txt"
  boot_sess="inbox_watch_spec_boot_$$"
  tmux kill-session -t "$boot_sess" >/dev/null 2>&1 || true
  mkdir -p "$tmp/epsilon/_dev_team/standup"
  EP="$tmp/epsilon/_dev_team/standup"
  echo "e | @Deb | hallo" > "$EP/_inbox.md"
  cat > "$tmp/epsilon/_dev_team/dev-team.env" <<ENVEOF
export TEAM_LEAD="Deb"
export MUX_SESSION="$boot_sess"
export PROJECT_ROOT="$tmp/epsilon"
export BOOT_CMD="echo PROJECT_ROOT=\$PROJECT_ROOT >> $boot_marker; sleep 30"
ENVEOF
  python3 - "$tmp/registry.json" "$tmp/epsilon" "$EP" <<'PY'
import json, sys
p, path, standup = sys.argv[1], sys.argv[2], sys.argv[3]
d = json.load(open(p))
d["projects"].append({"uid": "epsilon", "name": "epsilon", "path": path, "standup": standup, "status": "active"})
json.dump(d, open(p, "w"))
PY
  BOBNET_MUX=tmux DEV_TEAM_REGISTRY="$tmp/registry.json" INBOX_WATCH_STATE="$tmp/state" INBOX_WATCH_BOOT=1 bash "$BIN" >/dev/null 2>&1
  sleep 1
  t "(i) BOOT_CMD sieht Env-Werte aus dev-team.env (PROJECT_ROOT nicht leer)" "1" "$(grep -Fc "PROJECT_ROOT=$tmp/epsilon" "$boot_marker" 2>/dev/null || echo 0)"
  tmux kill-session -t "$boot_sess" >/dev/null 2>&1 || true

  # (j) dev-team.env vorhanden (MUX_SESSION bekannt), aber ohne BOOT_CMD -> weiterhin "Boot
  # nicht möglich", kein Crash. Die neue start_cmd-Konstruktion (liest+quoted envf VOR der
  # boot_cmd-Prüfung) darf diesen bestehenden Fall nicht verändern/brechen.
  mkdir -p "$tmp/zeta/_dev_team/standup"
  ZE="$tmp/zeta/_dev_team/standup"
  echo "z | @Deb | hallo" > "$ZE/_inbox.md"
  zeta_sess="inbox_watch_spec_zeta_$$"
  printf 'export TEAM_LEAD="Deb"\nexport MUX_SESSION="%s"\n' "$zeta_sess" > "$tmp/zeta/_dev_team/dev-team.env"
  python3 - "$tmp/registry.json" "$tmp/zeta" "$ZE" <<'PY'
import json, sys
p, path, standup = sys.argv[1], sys.argv[2], sys.argv[3]
d = json.load(open(p))
d["projects"].append({"uid": "zeta", "name": "zeta", "path": path, "standup": standup, "status": "active"})
json.dump(d, open(p, "w"))
PY
  out="$(BOBNET_MUX=tmux DEV_TEAM_REGISTRY="$tmp/registry.json" INBOX_WATCH_STATE="$tmp/state" INBOX_WATCH_BOOT=1 bash "$BIN" 2>/dev/null)"; rc=$?
  t "(j) fehlendes BOOT_CMD -> exit weiterhin 0" "0" "$rc"
  t "(j) ... unveränderte Meldung, kein Crash" "1" "$(printf '%s\n' "$out" | grep -c 'zeta:.*Boot nicht möglich')"
else
  echo "HINWEIS: tmux nicht verfügbar — Boot-Pfad-Tests (i)/(j) übersprungen"
fi

# ── Anti-Lärm-Batch Welle 1: Self-Write · Feld-Regression (#56) · Severity · Off-Duty ·
#    Session-down · Alt-State-Kompat. Jeweils EIGENE Projekte, damit diese Blöcke unabhängig vom
#    alpha/beta/delta-Narrativ oben bleiben (keine Reihenfolge-Kopplung).
reg_add() { # reg_add <uid> <path> <standup>
  python3 - "$tmp/registry.json" "$1" "$2" "$3" <<'PY'
import json, sys
p, uid, path, standup = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
d = json.load(open(p))
d["projects"].append({"uid": uid, "name": uid, "path": path, "standup": standup, "status": "active"})
json.dump(d, open(p, "w"))
PY
}

# ── (k) Self-Write-Erkennung (#56): reine Lead-Eigenschrift wird NICHT genudged ─────────────
mkdir -p "$tmp/eta/_dev_team/standup"
ET="$tmp/eta/_dev_team/standup"
printf 'export TEAM_LEAD="Nia"\nexport MUX_SESSION="eta_sess"\n' > "$tmp/eta/_dev_team/dev-team.env"
reg_add eta "$tmp/eta" "$ET"
echo "hallo welt | @Nia | initial" > "$ET/_inbox.md"
echo "$(now) | idle | start" > "$ET/Nia.log"
MAXN=3
out="$(run)"
t "(k) eta Erstkontakt nudgt normal (keine Baseline, konservativ)" "1" "$(printf '%s\n' "$out" | grep -c '\] eta: NUDGE #1')"
echo "$(now) | idle | zurueck" >> "$ET/Nia.log"
out="$(run)"
t "(k) eta Nudge verifiziert (Baseline jetzt gesetzt)" "1" "$(printf '%s\n' "$out" | grep -c '\] eta: Nudge verifiziert')"

echo "$(now) | @Nia | Notiz an mich selbst — (Nia)" >> "$ET/_inbox.md"
out="$(run)"
t "(k) reine Lead-Eigenschrift wird NICHT genudged" "0" "$(printf '%s\n' "$out" | grep -c '\] eta: NUDGE')"
t "(k) self-write wird geloggt + still finalisiert" "1" "$(printf '%s\n' "$out" | grep -c '\] eta:.*self-write')"
t "(k) Summary zählt Self-Write-Finalize separat (n_selfwrite)" "1" \
  "$(printf '%s\n' "$out" | grep -cE '── inbox-watch:.*, 1 self-write-finalisiert')"
out="$(run)"
t "(k) danach ok (unverändert) — Baseline korrekt vorgerückt" "1" "$(printf '%s\n' "$out" | grep -c '\] eta: ok')"

echo "$(now) | @Nia | Zweite Notiz — (Nia) 🐻" >> "$ET/_inbox.md"
out="$(run)"
t "(k) trailing Emoji macht das Autor-Endfeld nichtkanonisch → KEIN self-write" "0" "$(printf '%s\n' "$out" | grep -c '\] eta:.*self-write')"
t "(k) trailing Emoji wird stattdessen normal genudged" "1" "$(printf '%s\n' "$out" | grep -c '\] eta: NUDGE #1')"
echo "$(now) | idle | Emoji-Fall gelesen" >> "$ET/Nia.log"
run >/dev/null

echo "$(now) | @Nia | Dritte Notiz — Nia" >> "$ET/_inbox.md"
out="$(run)"
t "(k) Autor ohne Klammern ist nichtkanonisch → KEIN self-write" "0" "$(printf '%s\n' "$out" | grep -c '\] eta:.*self-write')"
t "(k) Autor ohne Klammern wird stattdessen normal genudged" "1" "$(printf '%s\n' "$out" | grep -c '\] eta: NUDGE #1')"
echo "$(now) | idle | Klammer-Fall gelesen" >> "$ET/Nia.log"
run >/dev/null

echo "$(now) | @Nia | eigene Notiz — (Nia)" >> "$ET/_inbox.md"
echo "$(now) | @Nia | SCUT (via email, von Kunde): dringende Frage" >> "$ET/_inbox.md"
out="$(run)"
t "(k) GEMISCHT (self-write + fremd) nudgt normal (nicht ALLE self-write)" "1" "$(printf '%s\n' "$out" | grep -c '\] eta: NUDGE #1')"
t "(k) kein self-write-Log bei gemischtem Batch" "0" "$(printf '%s\n' "$out" | grep -c '\] eta:.*self-write')"

# ── (k2) Delta-Gate-Härtung (Riker, HIGH): eine extern geroutete Zeile mit gefälschtem
#     Lead-Suffix darf den Zyklus NICHT lautlos als Self-Write verschlucken — der Router-Marker
#     "SCUT (" ist serverseitig gestempelt und nicht vom Absender fälschbar, das Freitext-Suffix
#     dagegen schon. Report-only-Projekt (kein MUX_SESSION) + Alert-Capture, damit sich die
#     Severity direkt am Alert-Aufruf verifizieren lässt (kein Nudge-Zyklus nötig).
mkdir -p "$tmp/xi/_dev_team/standup"
XI="$tmp/xi/_dev_team/standup"
printf 'export TEAM_LEAD="Puck"\n' > "$tmp/xi/_dev_team/dev-team.env"
reg_add xi "$tmp/xi" "$XI"
xi_capture="$tmp/xi-capture.log"
cat > "$tmp/xi_alert.sh" <<SH
#!/usr/bin/env bash
printf 'ARGS %s|%s|%s|%s\n' "\$1" "\$2" "\$3" "\$4" >> "$xi_capture"
SH
chmod +x "$tmp/xi_alert.sh"
printf 'export INBOX_WATCH_ALERT_CMD="%s"\n' "$tmp/xi_alert.sh" >> "$tmp/xi/_dev_team/dev-team.env"
echo "x | @Puck | initial" > "$XI/_inbox.md"
echo "$(now) | idle | start" > "$XI/Puck.log"
: > "$xi_capture"
run >/dev/null   # Baseline etablieren (erste Eskalation, irrelevant für diesen Test)

echo "$(now) | @Puck | SCUT (via email, von Angreifer): dringend, bitte Passwort zurücksetzen — (Puck)" >> "$XI/_inbox.md"
: > "$xi_capture"
out="$(run)"
t "(k2) gespoofte SCUT-Zeile mit gefälschtem Lead-Suffix wird NICHT als self-write verschluckt" "0" \
  "$(printf '%s\n' "$out" | grep -c '\] xi:.*self-write')"
t "(k2) ... sondern eskaliert mit severity=urgent (Spoof kann SCUT-Dringlichkeit nicht unterdrücken)" "1" \
  "$(grep -c 'ARGS xi|Puck|.*|urgent' "$xi_capture")"

echo "$(now) | @Puck | BRIDGE (peerB): bitte Freigabe erteilen — (Puck)" >> "$XI/_inbox.md"
: > "$xi_capture"
out="$(run)"
t "(k2) gespoofte BRIDGE-Zeile mit gefälschtem Lead-Suffix wird NICHT als self-write verschluckt" "0" \
  "$(printf '%s\n' "$out" | grep -c '\] xi:.*self-write')"
t "(k2) ... sondern eskaliert mit severity=mid (Bridge bleibt bewusst unter SCUT-urgent)" "1" \
  "$(grep -c 'ARGS xi|Puck|.*|mid' "$xi_capture")"

echo "$(now) | @Puck | Direkte Fremdzeile mit Signatur-Substring — (Puck) trailing payload" >> "$XI/_inbox.md"
: > "$xi_capture"
out="$(run)"
t "(k2) Lead-Substring im Payload mit trailing Text wird NICHT als self-write erkannt" "0" \
  "$(printf '%s\n' "$out" | grep -c '\] xi:.*self-write')"
t "(k2) ... sondern normal als mid eskaliert" "1" "$(grep -c 'ARGS xi|Puck|.*|mid' "$xi_capture")"

echo "$(now) | @Puck | Direkte Fremdzeile — (Puck) — (Mallory)" >> "$XI/_inbox.md"
: > "$xi_capture"
out="$(run)"
t "(k2) Payload-Lead vor echtem Fremdautor wird NICHT als self-write erkannt" "0" \
  "$(printf '%s\n' "$out" | grep -c '\] xi:.*self-write')"
t "(k2) Parser nimmt den LETZTEN Autor und eskaliert mid" "1" "$(grep -c 'ARGS xi|Puck|.*|mid' "$xi_capture")"

echo "$(now) | @Puck | erledigt, danke — (Puck)" >> "$XI/_inbox.md"
out="$(run)"
t "(k2) echte Lead-Eigenschrift OHNE SCUT-Marker bleibt weiterhin still finalisiert" "1" \
  "$(printf '%s\n' "$out" | grep -c '\] xi:.*self-write')"

# ── (k3) Rollen-UID != Persona: team.config ist die eindeutige Zuordnung. Sowohl der stabile
#     Log-/Routing-Key als auch die sichtbare Persona sind als EXAKTER kanonischer Autor gültig;
#     ein beliebiger Fremdautor bleibt fremd (Feld-Fund claude-tools, Garfield 2026-07-17).
mkdir -p "$tmp/persona/_dev_team/standup"
PE="$tmp/persona/_dev_team/standup"
printf 'export TEAM_LEAD="bobnet-infra"\n' > "$tmp/persona/_dev_team/dev-team.env"
cat > "$PE/team.config.json" <<'JSON'
{ "members": [ { "name": "Garfield", "uid": "bobnet-infra" } ] }
JSON
reg_add persona "$tmp/persona" "$PE"
echo "x | @bobnet-infra | initial" > "$PE/_inbox.md"
echo "$(now) | idle | start" > "$PE/bobnet-infra.log"
run >/dev/null   # Report-only-Erstkontakt finalisiert und etabliert die ilines-Baseline.

echo "$(now) | @bobnet-infra | Persona-Notiz — (Garfield)" >> "$PE/_inbox.md"
out="$(run)"
t "(k3) kanonische Persona-Signatur wird trotz TEAM_LEAD=Rollen-UID als self-write erkannt" "1" \
  "$(printf '%s\n' "$out" | grep -c '\] persona:.*self-write')"

echo "$(now) | @bobnet-infra | UID-Notiz — (bobnet-infra)" >> "$PE/_inbox.md"
out="$(run)"
t "(k3) exakte TEAM_LEAD-UID bleibt zusätzlich als self-write-Autor gültig" "1" \
  "$(printf '%s\n' "$out" | grep -c '\] persona:.*self-write')"

echo "$(now) | @bobnet-infra | fremde Notiz — (Mallory)" >> "$PE/_inbox.md"
out="$(run)"
t "(k3) beliebiger Fremdautor bleibt trotz Persona-Alias fremd" "0" \
  "$(printf '%s\n' "$out" | grep -c '\] persona:.*self-write')"
t "(k3) Fremdautor läuft durch den normalen Report-only-Pfad" "1" \
  "$(printf '%s\n' "$out" | grep -c '\] persona: NEU.*VERSCHLUCKT')"

cat > "$PE/team.config.json" <<'JSON'
{ "members": [
  { "name": "Garfield", "uid": "bobnet-infra" },
  { "name": "Mallory", "uid": "bobnet-infra" }
] }
JSON
echo "$(now) | @bobnet-infra | mehrdeutige Persona — (Garfield)" >> "$PE/_inbox.md"
out="$(run)"
t "(k3) mehrdeutiges UID→Name-Mapping schaltet keinen Persona-Alias frei (fail-closed)" "0" \
  "$(printf '%s\n' "$out" | grep -c '\] persona:.*self-write')"

echo "$(now) | @bobnet-infra | UID trotz Mehrdeutigkeit — (bobnet-infra)" >> "$PE/_inbox.md"
out="$(run)"
t "(k3) mehrdeutige Config fällt auf die exakte TEAM_LEAD-UID zurück" "1" \
  "$(printf '%s\n' "$out" | grep -c '\] persona:.*self-write')"

printf '{ kaputtes json\n' > "$PE/team.config.json"
echo "$(now) | @bobnet-infra | Persona bei kaputter Config — (Garfield)" >> "$PE/_inbox.md"
out="$(run)"
t "(k3) kaputte team.config schaltet keinen Persona-Alias frei (fail-closed)" "0" \
  "$(printf '%s\n' "$out" | grep -c '\] persona:.*self-write')"

echo "$(now) | @bobnet-infra | UID bei kaputter Config — (bobnet-infra)" >> "$PE/_inbox.md"
out="$(run)"
t "(k3) kaputte Config fällt ebenfalls auf die exakte TEAM_LEAD-UID zurück" "1" \
  "$(printf '%s\n' "$out" | grep -c '\] persona:.*self-write')"

cat > "$PE/team.config.json" <<'JSON'
{ "members": [ { "name": "Gar\u0000field", "uid": "bobnet-infra" } ] }
JSON
echo "$(now) | @bobnet-infra | C0-transformierter Alias — (Garfield)" >> "$PE/_inbox.md"
out="$(run)"
t "(k3) C0-Zeichen im Config-Namen können durch Bash-NUL-Strip keinen Alias erzeugen" "0" \
  "$(printf '%s\n' "$out" | grep -c '\] persona:.*self-write')"

# ── (l) Feld-Regression (#56): fremder Eintrag → max MAXN Nudges + 1 Eskalation; die Antwort des
#     Leads (self-signed) startet KEINEN neuen Zyklus (das war genau der Feld-Bug: >12-Nudge-
#     Serien, weil die eigene Antwort als "neue Inbox-Änderung" durchging).
mkdir -p "$tmp/theta/_dev_team/standup"
TH="$tmp/theta/_dev_team/standup"
printf 'export TEAM_LEAD="Deb2"\nexport MUX_SESSION="theta_sess"\n' > "$tmp/theta/_dev_team/dev-team.env"
reg_add theta "$tmp/theta" "$TH"
echo "x | @Deb2 | initial" > "$TH/_inbox.md"
echo "$(now) | idle | start" > "$TH/Deb2.log"
MAXN=3
run >/dev/null   # Baseline etablieren + verifizieren
echo "$(now) | idle | zurueck" >> "$TH/Deb2.log"
run >/dev/null

echo "$(now) | @Deb2 | SCUT (via email, von Kunde): bitte Vertrag pruefen" >> "$TH/_inbox.md"
echo "$(now) | idle | warte" > "$TH/Deb2.log"
out1="$(run)"; out2="$(run)"; out3="$(run)"; out4="$(run)"
t "(l) genau 3 Nudges vor der Eskalation" "3" \
  "$(printf '%s\n%s\n%s\n%s\n' "$out1" "$out2" "$out3" "$out4" | grep -c 'theta: NUDGE #')"
t "(l) NUDGE #1/#2/#3 in dieser Reihenfolge" "1" "$(printf '%s\n' "$out1" | grep -c 'theta: NUDGE #1')"
t "(l) ...#2" "1" "$(printf '%s\n' "$out2" | grep -c 'theta: NUDGE #2')"
t "(l) ...#3" "1" "$(printf '%s\n' "$out3" | grep -c 'theta: NUDGE #3')"
t "(l) 4. Lauf: genau 1 Eskalation (erschöpft)" "1" "$(printf '%s\n' "$out4" | grep -c 'theta:.*erschöpft.*VERSCHLUCKT')"
t "(l) 4. Lauf: KEIN 4. Nudge" "0" "$(printf '%s\n' "$out4" | grep -c 'theta: NUDGE #4')"

echo "$(now) | @Deb2 | erledigt, danke — (Deb2)" >> "$TH/_inbox.md"
out="$(run)"
t "(l) Lead-Antwort (self-signed) löst KEINEN neuen Nudge-Zyklus aus" "0" "$(printf '%s\n' "$out" | grep -c 'theta: NUDGE')"
t "(l) ... sondern self-write, still finalisiert" "1" "$(printf '%s\n' "$out" | grep -c 'theta:.*self-write')"
out="$(run)"
t "(l) danach ok (unverändert) — keine Endlos-Nudge-Serie mehr (Kern des #56-Feld-Bugs)" "1" \
  "$(printf '%s\n' "$out" | grep -c 'theta: ok')"

# ── (m) Severity-Klassifikation + ALERT_CMD-v2-Kontrakt (Args + Env) ────────────────────────
mkdir -p "$tmp/iota/_dev_team/standup"
IO="$tmp/iota/_dev_team/standup"
printf 'export TEAM_LEAD="Kai"\n' > "$tmp/iota/_dev_team/dev-team.env"   # kein MUX_SESSION -> report-only
reg_add iota "$tmp/iota" "$IO"
capture="$tmp/iota-capture.log"
cat > "$tmp/alert_capture.sh" <<SH
#!/usr/bin/env bash
printf 'ARGS %s|%s|%s|%s\n' "\$1" "\$2" "\$3" "\$4" >> "$capture"
printf 'ENV reason=%s source=%s\n' "\$INBOX_WATCH_REASON" "\$INBOX_WATCH_SOURCE" >> "$capture"
SH
chmod +x "$tmp/alert_capture.sh"
printf 'export INBOX_WATCH_ALERT_CMD="%s"\n' "$tmp/alert_capture.sh" >> "$tmp/iota/_dev_team/dev-team.env"
echo "x | @Kai | initial" > "$IO/_inbox.md"
echo "$(now) | idle | start" > "$IO/Kai.log"
: > "$capture"
run >/dev/null   # erste Eskalation etabliert nur die Baseline, Severity hier irrelevant

echo "$(now) | @Kai | SCUT (via email, von Kunde X): dringende Frage" >> "$IO/_inbox.md"
: > "$capture"
run >/dev/null
t "(m) SCUT-via-Marker -> severity=urgent (4. Alert-Arg)" "1" "$(grep -c 'ARGS iota|Kai|.*|urgent' "$capture")"
t "(m) Alert-Env INBOX_WATCH_SOURCE=inbox" "1" "$(grep -c 'ENV reason=.*source=inbox' "$capture")"

echo "y | UNGERICHTET (via email, von Kunde2) | allgemeine frage" >> "$IO/_review-queue.md"
: > "$capture"
run >/dev/null
t "(m) Review-Queue-Wachstum -> severity=urgent" "1" "$(grep -c 'ARGS iota|Kai|.*|urgent' "$capture")"
t "(m) Alert-Env INBOX_WATCH_SOURCE=review-queue" "1" "$(grep -c 'ENV reason=.*source=review-queue' "$capture")"

echo "$(now) | @Kai | einfache interne Nachricht ohne Marker" >> "$IO/_inbox.md"
: > "$capture"
out="$(run)"
t "(m) normale fremde Zeile -> severity=mid" "1" "$(grep -c 'ARGS iota|Kai|.*|mid' "$capture")"
t "(m) mid mit Default-MIN_SEVERITY=mid wird ESKALIERT (nicht gated)" "1" "$(printf '%s\n' "$out" | grep -c 'iota:.*ESKALIERT')"

echo "$(now) | @Kai | noch eine interne Nachricht ohne Marker" >> "$IO/_inbox.md"
: > "$capture"
out="$(INBOX_WATCH_ALERT_MIN_SEVERITY=urgent run)"
t "(m) MIN_SEVERITY=urgent gate't ein 'mid'-Event (kein Alert-Aufruf)" "0" "$(wc -l < "$capture" | tr -d ' ')"
t "(m) gegatetes Event korrekt geloggt (nicht VERSCHLUCKT)" "1" "$(printf '%s\n' "$out" | grep -c 'iota:.*unterhalb Mindest-Severity')"
t "(m) gegatet zählt NICHT als VERSCHLUCKT" "0" "$(printf '%s\n' "$out" | grep -c 'iota:.*VERSCHLUCKT')"
t "(m) Summary zählt unterhalb-Mindest-Severity separat (1)" "1" \
  "$(printf '%s\n' "$out" | grep -cE '── inbox-watch:.*, 1 unterhalb-Mindest-Severity, ')"

echo "z | UNGERICHTET (via email, von Kunde3) | dritte frage" >> "$IO/_review-queue.md"
: > "$capture"
out="$(INBOX_WATCH_ALERT_MIN_SEVERITY=urgent run)"
t "(m) urgent übersteht selbst MIN_SEVERITY=urgent (wird trotzdem eskaliert)" "1" \
  "$(grep -c 'ARGS iota|Kai|.*|urgent' "$capture")"

# ── (n) Off-Duty: unterdrückt Nudges/Alerts komplett; Auto-Clear bei Heartbeat NACH der Flag-mtime.
#     Feste synthetische Zeitstempel statt $(now): eine Heartbeat-Log-Zeile hat nur Minuten-
#     Auflösung, ein Vergleich gegen die sekundengenaue Datei-mtime des Flags wäre sonst ein
#     Zeitfenster-Rennen (0.14.0-Lehre: Zeilenzahl statt Timestamp, wo immer es geht — hier
#     GEHT es nicht, also stattdessen eindeutig auseinanderliegende feste Zeitstempel).
mkdir -p "$tmp/kappa/_dev_team/standup"
KP="$tmp/kappa/_dev_team/standup"
printf 'export TEAM_LEAD="Milo"\nexport MUX_SESSION="kappa_sess"\n' > "$tmp/kappa/_dev_team/dev-team.env"
reg_add kappa "$tmp/kappa" "$KP"
echo "x | @Milo | initial" > "$KP/_inbox.md"
echo "2020-01-01 00:00 | idle | start" > "$KP/Milo.log"
run >/dev/null   # NUDGE #1
echo "2020-01-01 00:01 | idle | zurueck" >> "$KP/Milo.log"
run >/dev/null   # verifiziert -> final

touch -d "2020-06-01 00:00" "$KP/.off-duty"
echo "irgendwas | @Milo | neue fremde Nachricht waehrend Feierabend" >> "$KP/_inbox.md"
out="$(run)"
t "(n) Off-Duty unterdrückt Nudge komplett" "0" "$(printf '%s\n' "$out" | grep -c 'kappa: NUDGE')"
t "(n) Off-Duty-Log-Zeile erscheint" "1" "$(printf '%s\n' "$out" | grep -c 'kappa: Off-Duty')"
ok "(n) Off-Duty-Flag existiert noch (kein Auto-Clear ohne späteren Heartbeat)" test -f "$KP/.off-duty"

echo "2020-12-01 00:00 | idle | bin wieder da" >> "$KP/Milo.log"
out="$(run)"
t "(n) Auto-Clear löscht das Off-Duty-Flag (Heartbeat NACH der Flag-mtime)" "1" \
  "$(printf '%s\n' "$out" | grep -c 'kappa:.*Off-Duty-Flag gelöscht')"
ok "(n) Flag-Datei tatsächlich weg" bash -c "! test -f '$KP/.off-duty'"
out="$(run)"
t "(n) danach normaler Betrieb — NEU wird wieder erkannt/genudged" "1" "$(printf '%s\n' "$out" | grep -c 'kappa: NUDGE')"

# ── (o) Session-down-Eskalation (#55): genau EINMAL pro Down-Vorgang, Reset bei Session-up,
#     Off-Duty unterdrückt auch das. Fake-tmux-Shim (Muster aus recycle_spec.sh) statt echtem
#     Multiplexer — deterministisch, kein Host-tmux nötig.
mkdir -p "$tmp/lambda/_dev_team/standup" "$tmp/lambda_mux" "$tmp/lambda_bin"
LM="$tmp/lambda/_dev_team/standup"
printf 'export TEAM_LEAD="Rosa"\nexport MUX_SESSION="lambda_sess"\n' > "$tmp/lambda/_dev_team/dev-team.env"
reg_add lambda "$tmp/lambda" "$LM"
echo "x | @Rosa | initial" > "$LM/_inbox.md"
echo "$(now) | idle | start" > "$LM/Rosa.log"
cat > "$tmp/lambda_bin/tmux" <<'SH'
#!/usr/bin/env bash
S="${FAKE_MUX_DIR:?}"
cmd="${1:-}"; shift || true
case "$cmd" in
  has-session) [ -e "$S/${2:?}" ] ;;
  *) exit 0 ;;
esac
SH
chmod +x "$tmp/lambda_bin/tmux"
lambda_alerts="$tmp/lambda-alerts.log"
cat > "$tmp/lambda_alert.sh" <<SH
#!/usr/bin/env bash
printf 'ALERT uid=%s severity=%s source=%s\n' "\$1" "\$4" "\$INBOX_WATCH_SOURCE" >> "$lambda_alerts"
SH
chmod +x "$tmp/lambda_alert.sh"
printf 'export INBOX_WATCH_ALERT_CMD="%s"\n' "$tmp/lambda_alert.sh" >> "$tmp/lambda/_dev_team/dev-team.env"
run_real() {
  env DEV_TEAM_REGISTRY="$tmp/registry.json" INBOX_WATCH_STATE="$tmp/state" \
      BOBNET_MUX=tmux PATH="$tmp/lambda_bin:$PATH" FAKE_MUX_DIR="$tmp/lambda_mux" \
      bash "$BIN" 2>/dev/null
}

out="$(run_real)"
t "(o) Session down (kein Boot) → EINMALIGE Eskalation (severity=urgent)" "1" \
  "$(printf '%s\n' "$out" | grep -c 'lambda:.*Down-Eskalation: escalated')"
t "(o) Alert-Cmd feuert genau einmal" "1" "$(grep -c 'ALERT uid=lambda severity=urgent source=session-down' "$lambda_alerts")"

out="$(run_real)"
t "(o) weiterer Tick, Session weiterhin down → KEIN erneuter Alert" "1" \
  "$(printf '%s\n' "$out" | grep -c 'lambda:.*weiterhin down.*bereits eskaliert')"
t "(o) Alert-Cmd feuert weiterhin nur einmal" "1" "$(wc -l < "$lambda_alerts" | tr -d ' ')"

: > "$tmp/lambda_mux/lambda_sess"   # Session kommt zurück
out="$(run_real)"
t "(o) Session wieder da → Down-Eskalation zurückgesetzt (Marker weg)" "1" \
  "$(printf '%s\n' "$out" | grep -c 'lambda:.*wieder da.*zurückgesetzt')"

rm -f "$tmp/lambda_mux/lambda_sess"; echo "$(now) | idle | warte" > "$LM/Rosa.log"
echo "noch eine nachricht" >> "$LM/_inbox.md"
out="$(run_real)"
t "(o) neue Down-Episode eskaliert wieder frisch" "1" \
  "$(printf '%s\n' "$out" | grep -c 'lambda:.*Down-Eskalation: escalated')"
t "(o) Alert-Cmd insgesamt zweimal ausgelöst (eine Eskalation pro Down-Episode)" "2" \
  "$(wc -l < "$lambda_alerts" | tr -d ' ')"

touch "$LM/.off-duty"
out="$(run_real)"
t "(o) Off-Duty unterdrückt auch die Session-down-Eskalation" "1" "$(printf '%s\n' "$out" | grep -c 'lambda: Off-Duty')"
t "(o) kein dritter Alert während Off-Duty" "2" "$(wc -l < "$lambda_alerts" | tr -d ' ')"
rm -f "$LM/.off-duty"

# ── (p) Alt-State-Kompat: Self-Write-Erkennung ohne ilines-Baseline bewusst NICHT möglich —
#     eine Lead-eigene Signatur-Zeile wird trotzdem normal genudged (konservativ). Eigenes,
#     frisches Projekt mit HANDGESCHRIEBENEM Alt-Format-State (nackte Signatur, kein ilines) —
#     delta oben ist ungeeignet: dessen State heilte in Test (f) bereits auf das neue Format.
mkdir -p "$tmp/mu/_dev_team/standup"
MU="$tmp/mu/_dev_team/standup"
printf 'export TEAM_LEAD="Theo"\nexport MUX_SESSION="mu_sess"\n' > "$tmp/mu/_dev_team/dev-team.env"
reg_add mu "$tmp/mu" "$MU"
echo "erste zeile | @Theo | initial" > "$MU/_inbox.md"
musig="$(wc -c < "$MU/_inbox.md" | tr -d ' '):0:0"
printf '%s' "$musig" > "$tmp/state/mu.state"   # Alt-Format: nackte Signatur, kein ilines
echo "$(now) | idle | warte" > "$MU/Theo.log"
echo "$(now) | @Theo | eigene notiz — (Theo)" >> "$MU/_inbox.md"
out="$(run)"
t "(p) Alt-Format-State ohne ilines: Self-Write-Erkennung nicht möglich → normaler Nudge" "1" \
  "$(printf '%s\n' "$out" | grep -c 'mu: NUDGE #1')"
t "(p) ... kein self-write-Log (Erkennung mangels Baseline unmöglich, konservativ)" "0" \
  "$(printf '%s\n' "$out" | grep -c 'mu:.*self-write')"

# ── (q) Marvin-Lücke 1: Legacy-PENDING ohne ilines (0.14/0.15-Format, liegt live in allen
#     Flotten-State-Dirs am Rollout-Tag). Handgeschriebener PENDING-State ohne das ilines-Feld
#     beweist: kein Crash, kein Self-Write-Versuch (Baseline fehlt, konservativ), normaler
#     Zyklus läuft weiter, Severity bleibt trotz fehlender Baseline korrekt (mid statt Crash).
mkdir -p "$tmp/omicron/_dev_team/standup"
OM="$tmp/omicron/_dev_team/standup"
printf 'export TEAM_LEAD="Fenn"\n' > "$tmp/omicron/_dev_team/dev-team.env"   # report-only + Alert-Capture
reg_add omicron "$tmp/omicron" "$OM"
om_capture="$tmp/omicron-capture.log"
cat > "$tmp/omicron_alert.sh" <<SH
#!/usr/bin/env bash
printf 'ARGS %s|%s|%s|%s\n' "\$1" "\$2" "\$3" "\$4" >> "$om_capture"
SH
chmod +x "$tmp/omicron_alert.sh"
printf 'export INBOX_WATCH_ALERT_CMD="%s"\n' "$tmp/omicron_alert.sh" >> "$tmp/omicron/_dev_team/dev-team.env"
# BEIDE Zeilen sehen wie Lead-Eigenschrift aus (Signatur "— (Fenn)") — das ist Absicht: ein
# permissiver Mutant, der ein fehlendes ilines als "0" statt "unverfügbar" behandelt, würde die
# GESAMTE Datei (inkl. der "alten" ersten Zeile) fälschlich als "neu" ansehen und, weil ALLE
# Zeilen self-signiert aussehen, lautlos self-write-finalisieren — korrektes Verhalten muss den
# Self-Write-Versuch mangels Baseline komplett auslassen und stattdessen normal eskalieren,
# unabhängig davon, wie die Zeilen aussehen. Nur so ist der Test mutationssensitiv (verifiziert).
echo "erste zeile — (Fenn)" > "$OM/_inbox.md"
oldsig="$(wc -c < "$OM/_inbox.md" | tr -d ' '):0:0"
echo "$(now) | idle | schon zwei" > "$OM/Fenn.log"
echo "$(now) | idle | zeilen" >> "$OM/Fenn.log"
# Legacy-PENDING-State (Format vor diesem Batch): PENDING sig=... lines=... attempts=... OHNE ilines.
printf 'PENDING sig=%s lines=2 attempts=1' "$oldsig" > "$tmp/state/omicron.state"
echo "zweite zeile ebenfalls signiert — (Fenn)" >> "$OM/_inbox.md"
: > "$om_capture"
out="$(run)"
t "(q) Legacy-PENDING ohne ilines: kein Crash / keine Korrupt-Meldung" "0" \
  "$(printf '%s\n' "$out" | grep -c 'PENDING-State korrupt')"
t "(q) ... kein Self-Write-Versuch (Baseline fehlt, konservativ)" "0" \
  "$(printf '%s\n' "$out" | grep -c '\] omicron:.*self-write')"
t "(q) ... normaler Zyklus läuft weiter (report-only → Eskalation statt Absturz)" "1" \
  "$(printf '%s\n' "$out" | grep -c '\] omicron:.*kein Weckweg')"
t "(q) ... Severity trotz fehlender ilines-Baseline korrekt klassifiziert (mid, kein Crash)" "1" \
  "$(grep -c 'ARGS omicron|Fenn|.*|mid' "$om_capture")"
out="$(run)"
t "(q) State auf neues Format geheilt → danach ok (unverändert)" "1" \
  "$(printf '%s\n' "$out" | grep -c '\] omicron: ok')"

# ── (r) Marvin-Lücke 2: die info-Klassifikation wurde NIE erzeugt — der Zweig ließ sich
#     ersatzlos aus classify_severity() löschen, ohne dass die Suite rot ging (toter Code laut
#     Test). Reiner _inbox/-Datei-Churn OHNE begleitende neue _inbox.md-Zeile und OHNE
#     Review-Queue-Wachstum ist der einzige Weg zu info (s. inbox-watch.sh-Kopf Punkt 8) — bei
#     Default-MIN_SEVERITY=mid wird ein info-Event gegatet, NICHT alarmiert (kein Alert-Aufruf).
mkdir -p "$tmp/rho/_dev_team/standup"
RH="$tmp/rho/_dev_team/standup"
printf 'export TEAM_LEAD="Sable"\n' > "$tmp/rho/_dev_team/dev-team.env"   # report-only + Alert-Capture
reg_add rho "$tmp/rho" "$RH"
rho_capture="$tmp/rho-capture.log"
cat > "$tmp/rho_alert.sh" <<SH
#!/usr/bin/env bash
printf 'ARGS %s|%s|%s|%s\n' "\$1" "\$2" "\$3" "\$4" >> "$rho_capture"
SH
chmod +x "$tmp/rho_alert.sh"
printf 'export INBOX_WATCH_ALERT_CMD="%s"\n' "$tmp/rho_alert.sh" >> "$tmp/rho/_dev_team/dev-team.env"
echo "x | @Sable | initial" > "$RH/_inbox.md"
echo "$(now) | idle | start" > "$RH/Sable.log"
: > "$rho_capture"
run >/dev/null   # Baseline etablieren (erste Eskalation, Severity hier irrelevant)

mkdir -p "$RH/_inbox"; echo "anhang" > "$RH/_inbox/datei.txt"   # reiner Datei-Drop, keine neue Zeile
: > "$rho_capture"
out="$(run)"
t "(r) reiner _inbox/-Datei-Churn (keine neue Zeile, keine Queue) → severity=info" "1" \
  "$(printf '%s\n' "$out" | grep -c '\] rho:.*unterhalb Mindest-Severity (info < mid)')"
t "(r) info-Event zählt als unterhalb-Mindest-Severity, nicht als ESKALIERT" "0" \
  "$(printf '%s\n' "$out" | grep -c '\] rho:.*ESKALIERT')"
t "(r) kein Alert-Aufruf für ein gegatetes info-Event" "0" "$(wc -l < "$rho_capture" | tr -d ' ')"
t "(r) Summary zählt exakt 1 unterhalb-Mindest-Severity in diesem Tick" "1" \
  "$(printf '%s\n' "$out" | grep -cE '── inbox-watch:.*, 1 unterhalb-Mindest-Severity, ')"

echo "inbox_watch_spec: $pass passed, $fail failed"
[ "$fail" = 0 ]
