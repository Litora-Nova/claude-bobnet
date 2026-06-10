#!/usr/bin/env bash
# tests/git_identity_spec.sh — Behavior-Spec für scripts/git-identity.sh.
#
# SPEC-Quelle: team-rules/commits.md (Kanon PO 2026-06-02) + Script-Header.
# Format:  <Name> (<Projekt-Display> <role>) <DEV_TEAM_EMAIL>   (ohne role: "<Name> (<Display>) <Email>")
# Resolution: NAME=theme.personas[id].name · ROLE=positionLabel(i18n)→archetype.positionLong→"" ·
#             DISPLAY=dev-team.env PROJECT_NAME · EMAIL=DEV_TEAM_EMAIL (Default team@litora-nova.com).
# Fail-safe: fehlt/leer ein Pflichtfeld → klare stderr-Warnung, export gibt NICHTS aus (git-Default bleibt),
#            KEIN kaputtes "() <>".
#
# Black-Box: wir bauen Wegwerf-Theme/-Archetypen/-Env in mktemp -d und rufen das echte Script
# mit ENGINE_ROOT/DEV_TEAM_ENV/THEME darauf. KEINE echte Registry/theme angefasst.

set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_helper.sh
. "$HERE/_helper.sh"

GI="$SCRIPTS/git-identity.sh"

echo "git-identity.sh — Behavior-Spec"

# ── Fixture-Builder: ein vollständiges Wegwerf-Bobiverse in einem temp-dir ────────────────
TMP="$(mktemp -d "${TMPDIR:-/tmp}/git-identity-spec.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/themes/demo" "$TMP/archetypes"

cat > "$TMP/themes/demo/theme.json" <<'JSON'
{ "id":"demo","label":"Demo","defaultAvatar":"default.png",
  "personas":{
    "BOB-dashboard":{"name":"Garfield","positionLabel":{"de":"BobNet Architekt","en":"BobNet Architect"}},
    "BOB-backend":{"name":"Bill"},
    "BOB-noarch":{"name":"Nemo"}
  } }
JSON
cat > "$TMP/archetypes/backend.json" <<'JSON'
{ "archetype":"backend","positionLong":"Backend + Infra","idPattern":"BOB-backend" }
JSON
cat > "$TMP/env" <<'ENV'
export PROJECT_NAME="Claude-tools"
export DEV_TEAM_EMAIL="team@litora-nova.com"
ENV

# run <extra-env…> -- <args…> : Script mit Demo-Fixtures, optionalem Extra-Env.
run() {
  local envs=() ; while [ "${1:-}" != "--" ] && [ $# -gt 0 ]; do envs+=("$1"); shift; done
  shift || true
  env ENGINE_ROOT="$TMP" DEV_TEAM_ENV="$TMP/env" THEME=demo "${envs[@]}" bash "$GI" "$@"
}

# ── Happy-Path ────────────────────────────────────────────────────────────────────────────
it "print: name-lookup + i18n en → voller Identitäts-String"
eq "$(run HEARTBEAT_AGENT=Garfield -- print)" \
   "Garfield (Claude-tools BobNet Architect) <team@litora-nova.com>"

it "print: exakter THEME_AGENT_ID-Lookup ergibt dasselbe"
eq "$(run THEME_AGENT_ID=BOB-dashboard -- print)" \
   "Garfield (Claude-tools BobNet Architect) <team@litora-nova.com>"

it "print: i18n de wählt das deutsche positionLabel"
eq "$(run HEARTBEAT_AGENT=Garfield DEV_TEAM_LOCALE=de -- print)" \
   "Garfield (Claude-tools BobNet Architekt) <team@litora-nova.com>"

it "trailer: Co-Authored-By im exakten Persona-Format (ersetzt Claude-Trailer)"
eq "$(run HEARTBEAT_AGENT=Garfield -- trailer)" \
   "Co-Authored-By: Garfield (Claude-tools BobNet Architect) <team@litora-nova.com>"

it "export(author): enthält Full-Name + geteilte Email für AUTHOR und COMMITTER"
exp="$(run HEARTBEAT_AGENT=Garfield COMMIT_IDENTITY_MODE=author -- export)"
contains "$exp" "GIT_AUTHOR_NAME="
contains "$exp" "Garfield (Claude-tools BobNet Architect)"
contains "$exp" "GIT_COMMITTER_NAME="
contains "$exp" "GIT_AUTHOR_EMAIL="
contains "$exp" "team@litora-nova.com"

it "export(author): setzt KEINEN Co-Authored-By-Trailer (nur both/trailer tun das)"
not_contains "$exp" "GIT_COMMIT_TRAILER"

it "export(both): setzt Author-Env UND einen Co-Author-Trailer"
expb="$(run HEARTBEAT_AGENT=Garfield COMMIT_IDENTITY_MODE=both -- export)"
contains "$expb" "GIT_AUTHOR_NAME="
contains "$expb" "GIT_COMMIT_TRAILER="
contains "$expb" "Co-Authored-By: Garfield (Claude-tools BobNet Architect)"

# ── ROLE-Fallback-Kette: positionLabel → archetype.positionLong → "" ───────────────────────
it "role-fallback: ohne positionLabel zieht es positionLong aus dem Archetyp (idPattern-Match)"
eq "$(run HEARTBEAT_AGENT=Bill -- print)" \
   "Bill (Claude-tools Backend + Infra) <team@litora-nova.com>"

it "EDGE: fehlendes positionLabel UND kein Archetyp-Match → kein leeres '()', role weggelassen"
got="$(run HEARTBEAT_AGENT=Nemo -- print)"
eq "$got" "Nemo (Claude-tools) <team@litora-nova.com>"
not_contains "$got" "()"
not_contains "$got" "( )"

# ── EDGE: fehlende/teilweise Env ───────────────────────────────────────────────────────────
it "EDGE: fehlendes DEV_TEAM_EMAIL → Default team@litora-nova.com (kein <> -Müll)"
cat > "$TMP/env-noemail" <<'ENV'
export PROJECT_NAME="Claude-tools"
ENV
got="$(env ENGINE_ROOT="$TMP" DEV_TEAM_ENV="$TMP/env-noemail" THEME=demo HEARTBEAT_AGENT=Garfield bash "$GI" print)"
eq "$got" "Garfield (Claude-tools BobNet Architect) <team@litora-nova.com>"
not_contains "$got" "<>"

it "EDGE: fehlendes PROJECT_NAME → KEIN leeres '()', Warnung auf stderr, kein Crash"
cat > "$TMP/env-nodisplay" <<'ENV'
export DEV_TEAM_EMAIL="team@litora-nova.com"
ENV
got="$(env ENGINE_ROOT="$TMP" DEV_TEAM_ENV="$TMP/env-nodisplay" THEME=demo HEARTBEAT_AGENT=Garfield bash "$GI" print 2>/dev/null)"
# Display fällt auf "?" (Platzhalter), NICHT auf ein leeres "()".
not_contains "$got" "( BobNet"   # kein führendes-Space-Leerdisplay
not_contains "$got" "()"
ok env ENGINE_ROOT="$TMP" DEV_TEAM_ENV="$TMP/env-nodisplay" THEME=demo HEARTBEAT_AGENT=Garfield bash "$GI" print

# ── EDGE: fehlende theme.json → klarer Fehler, kein Crash, rc!=0 ───────────────────────────
it "EDGE: fehlende theme.json → rc!=0, keine Identitäts-Zeile auf stdout"
out="$(env ENGINE_ROOT="$TMP/does-not-exist" DEV_TEAM_ENV="$TMP/env" THEME=demo HEARTBEAT_AGENT=Garfield bash "$GI" print 2>/dev/null)"
eq "$out" ""
not_ok env ENGINE_ROOT="$TMP/does-not-exist" DEV_TEAM_ENV="$TMP/env" THEME=demo HEARTBEAT_AGENT=Garfield bash "$GI" print

it "EDGE: export bei fehlender theme.json gibt NICHTS aus (git-Default bleibt)"
out="$(env ENGINE_ROOT="$TMP/does-not-exist" DEV_TEAM_ENV="$TMP/env" THEME=demo HEARTBEAT_AGENT=Garfield bash "$GI" export 2>/dev/null)"
not_contains "$out" "GIT_AUTHOR_NAME"

# ── EDGE: unbekannter Name / kein Selektor → rc!=0 (fail-safe) ─────────────────────────────
it "EDGE: unbekannter HEARTBEAT_AGENT → rc!=0, keine kaputte Identität"
not_ok run HEARTBEAT_AGENT=Niemand -- print

it "EDGE: weder THEME_AGENT_ID noch HEARTBEAT_AGENT → rc!=0"
not_ok run -- print

it "EDGE: unbekannte THEME_AGENT_ID → rc!=0"
not_ok run THEME_AGENT_ID=BOB-ghost -- print

# ── THEMES_DIR: externes User-Themes-Verzeichnis schlägt Engine-Builtins ───────────────────
# Kanon (comms.md §6-Geist / PO 2026-06-10): Themes wohnen beim User — THEMES_DIR ist der
# Suchpfad VOR $ENGINE_ROOT/themes (Pendant zu Dashboard-NUXT_THEMES_DIR).
mkdir -p "$TMP/user-themes/demo"
cat > "$TMP/user-themes/demo/theme.json" <<'JSON'
{ "id":"demo","label":"Demo (User)","defaultAvatar":"default.png",
  "personas":{ "BOB-dashboard":{"name":"Garfield","positionLabel":{"en":"User-Theme Architect"}} } }
JSON
it "THEMES_DIR: User-Theme gewinnt über Engine-Builtin"
eq "$(run THEMES_DIR="$TMP/user-themes" HEARTBEAT_AGENT=Garfield -- print)" \
   "Garfield (Claude-tools User-Theme Architect) <team@litora-nova.com>"

it "THEMES_DIR: Theme dort NICHT vorhanden → Fallback auf Engine-Builtin"
eq "$(run THEMES_DIR="$TMP/leeres-themes-dir" HEARTBEAT_AGENT=Garfield -- print)" \
   "Garfield (Claude-tools BobNet Architect) <team@litora-nova.com>"

# ── team.config: per-Team-Namens-Override (FR#21.3 — Lead heißt z.B. "Martin") ─────────────
cat > "$TMP/team.config.json" <<'JSON'
{ "members": [ { "name": "Martin", "id": "BOB-dashboard", "role": "Lead", "order": 1 } ] }
JSON
it "team.config: HEARTBEAT_AGENT=per-Team-Name → Member-Fallback (Name aus team.config, Rolle aus Theme)"
eq "$(run TEAM_CONFIG="$TMP/team.config.json" HEARTBEAT_AGENT=Martin -- print)" \
   "Martin (Claude-tools BobNet Architect) <team@litora-nova.com>"

it "team.config: THEME_AGENT_ID-Pfad → Member-Name überschreibt Theme-Persona-Name"
eq "$(run TEAM_CONFIG="$TMP/team.config.json" THEME_AGENT_ID=BOB-dashboard -- print)" \
   "Martin (Claude-tools BobNet Architect) <team@litora-nova.com>"

it "team.config: Theme-Persona-Name-Match hat Vorrang (Garfield bleibt Garfield)"
eq "$(run TEAM_CONFIG="$TMP/team.config.json" HEARTBEAT_AGENT=Garfield -- print)" \
   "Garfield (Claude-tools BobNet Architect) <team@litora-nova.com>"

it "team.config: unbekannter Name trotz team.config → rc!=0 (fail-safe bleibt)"
not_ok run TEAM_CONFIG="$TMP/team.config.json" HEARTBEAT_AGENT=Niemand -- print

it "team.config: kaputtes JSON → WARN, aber Theme-Lookup läuft weiter"
printf '{kaputt' > "$TMP/team.broken.json"
eq "$(run TEAM_CONFIG="$TMP/team.broken.json" HEARTBEAT_AGENT=Garfield -- print 2>/dev/null)" \
   "Garfield (Claude-tools BobNet Architect) <team@litora-nova.com>"

# ── team.config: Präzedenz + Robustheit der Override-Kette (Gate-Lücken Marvin 2026-06-11) ──
# Diese Checks pinnen die im Script-Header (Resolution) dokumentierte Vorrang-Kette explizit,
# damit eine Umstellung der Lookup-Reihenfolge sofort ROT wird statt still die Identität zu kippen.

it "team.config: Theme-Persona-Name-Match schlägt einen kollidierenden Member-Override (id-Pfad anders)"
# Member sagt 'Garfield'→BOB-backend, aber HEARTBEAT_AGENT matcht zuerst die Theme-Persona Garfield
# (BOB-dashboard). Der Persona-Name-Match läuft VOR dem Member-Fallback → Rolle bleibt dashboard.
printf '{ "members":[ {"name":"Garfield","id":"BOB-backend"} ] }' > "$TMP/team.collide.json"
eq "$(run TEAM_CONFIG="$TMP/team.collide.json" HEARTBEAT_AGENT=Garfield -- print)" \
   "Garfield (Claude-tools BobNet Architect) <team@litora-nova.com>"

it "team.config: Member OHNE id wird beim Name-Fallback ignoriert (kein Crash, fail-safe rc!=0)"
# Ein Member ohne 'id' darf den HEARTBEAT_AGENT-Fallback nicht als Treffer beanspruchen (er liefert
# keine Persona-Rolle) — und darf erst recht nicht crashen. Name matcht weder Theme noch valider Member.
printf '{ "members":[ {"name":"Waise","role":"Lead"} ] }' > "$TMP/team.noid.json"
not_ok run TEAM_CONFIG="$TMP/team.noid.json" HEARTBEAT_AGENT=Waise -- print

it "team.config: Member ohne id stört einen gültigen Theme-Lookup nicht"
eq "$(run TEAM_CONFIG="$TMP/team.noid.json" HEARTBEAT_AGENT=Garfield -- print)" \
   "Garfield (Claude-tools BobNet Architect) <team@litora-nova.com>"

it "team.config: STANDUP_DIR-Konvention (team.config.json daneben) wird ohne explizites TEAM_CONFIG gefunden"
# Produktionspfad: dev-team.env setzt STANDUP_DIR → $STANDUP_DIR/team.config.json wird implizit genutzt.
mkdir -p "$TMP/standup"
printf '{ "members":[ {"name":"Martin","id":"BOB-dashboard"} ] }' > "$TMP/standup/team.config.json"
eq "$(run STANDUP_DIR="$TMP/standup" HEARTBEAT_AGENT=Martin -- print)" \
   "Martin (Claude-tools BobNet Architect) <team@litora-nova.com>"

it "team.config: explizites TEAM_CONFIG schlägt die STANDUP_DIR-Konvention"
printf '{ "members":[ {"name":"Martin","id":"BOB-dashboard"} ] }' > "$TMP/team.explicit.json"
# STANDUP_DIR zeigt auf ein team.config mit FALSCHEM Namen — explizit muss gewinnen.
printf '{ "members":[ {"name":"FALSCH","id":"BOB-dashboard"} ] }' > "$TMP/standup/team.config.json"
eq "$(run TEAM_CONFIG="$TMP/team.explicit.json" STANDUP_DIR="$TMP/standup" THEME_AGENT_ID=BOB-dashboard -- print)" \
   "Martin (Claude-tools BobNet Architect) <team@litora-nova.com>"

it "team.config: export(author) trägt den Override-Namen in GIT_AUTHOR_NAME (nicht den Theme-Namen)"
expm="$(run TEAM_CONFIG="$TMP/team.explicit.json" THEME_AGENT_ID=BOB-dashboard COMMIT_IDENTITY_MODE=author -- export)"
contains "$expm" "GIT_AUTHOR_NAME=\"Martin (Claude-tools BobNet Architect)\""
contains "$expm" "GIT_COMMITTER_NAME=\"Martin (Claude-tools BobNet Architect)\""
not_contains "$expm" "Garfield"

# ── INTEGRATION: gegen die ECHTE bobiverse/theme.json + echte Archetypen (read-only) ───────
# Realer Stand (Phase-D-Follow-up 2026-06-02): die echte bobiverse/theme.json hat jetzt je Persona
# ein positionLabel (i18n {de,en}) → role MUSS aus dem Persona-positionLabel kommen (höchste Prio),
# NICHT mehr aus dem Archetyp-positionLong-Fallback. Dieser Test pinnt genau dieses Verhalten am
# echten Theme. (Den Archetyp-Fallback selbst deckt die isolierte 'role-fallback'-Spec oben ab.)
# ROLLENTAUSCH (PO-Kanon 2026-06-10): Dexter = Compliance, Marvin = QM/Tests — hier gepinnt.
it "INTEGRATION: echte theme.json → Dexter ist COMPLIANCE (Rollentausch-Kanon), kein leeres ()"
cat > "$TMP/env-real" <<'ENV'
export PROJECT_NAME="Acme Inc"
export DEV_TEAM_EMAIL="team@litora-nova.com"
ENV
real="$(env ENGINE_ROOT="$ENGINE_ROOT" DEV_TEAM_ENV="$TMP/env-real" THEME=bobiverse HEARTBEAT_AGENT=Dexter bash "$GI" print 2>/dev/null)"
eq "$real" "Dexter (Acme Inc Compliance) <team@litora-nova.com>"
not_contains "$real" "()"

it "INTEGRATION: echte theme.json → Marvin ist QM/TESTS (Rollentausch-Kanon)"
realm="$(env ENGINE_ROOT="$ENGINE_ROOT" DEV_TEAM_ENV="$TMP/env-real" THEME=bobiverse HEARTBEAT_AGENT=Marvin bash "$GI" print 2>/dev/null)"
eq "$realm" "Marvin (Acme Inc QM / Tests) <team@litora-nova.com>"

it "INTEGRATION: Rollentausch-Negativkontrolle — Dexter trägt NICHT mehr QM/Tests, Marvin NICHT mehr Compliance"
# Explizit gegen ein Zurückkippen des Tauschs (vor 2026-06-10 war Dexter=Tests, Marvin=Compliance).
not_contains "$real"  "QM / Tests"
not_contains "$realm" "Compliance"

it "INTEGRATION: getauschte Rollen auch in de-Locale gepinnt (Dexter=Compliance, Marvin=QM/Tests)"
realded="$(env ENGINE_ROOT="$ENGINE_ROOT" DEV_TEAM_ENV="$TMP/env-real" THEME=bobiverse HEARTBEAT_AGENT=Dexter DEV_TEAM_LOCALE=de bash "$GI" print 2>/dev/null)"
eq "$realded" "Dexter (Acme Inc Compliance) <team@litora-nova.com>"
realdem="$(env ENGINE_ROOT="$ENGINE_ROOT" DEV_TEAM_ENV="$TMP/env-real" THEME=bobiverse HEARTBEAT_AGENT=Marvin DEV_TEAM_LOCALE=de bash "$GI" print 2>/dev/null)"
eq "$realdem" "Marvin (Acme Inc QM / Tests) <team@litora-nova.com>"

it "INTEGRATION: echte theme.json → de-Locale wählt das deutsche positionLabel (Garfield → BobNet-Architekt)"
realde="$(env ENGINE_ROOT="$ENGINE_ROOT" DEV_TEAM_ENV="$TMP/env-real" THEME=bobiverse HEARTBEAT_AGENT=Garfield DEV_TEAM_LOCALE=de bash "$GI" print 2>/dev/null)"
eq "$realde" "Garfield (Acme Inc BobNet-Architekt) <team@litora-nova.com>"

summary
