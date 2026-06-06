#!/usr/bin/env bash
# tests/dashboard_registry_spec.sh — Black-Box-Spec für den Registry-Layer des
# Dashboards (dashboard/server/utils/registry.mjs): Pfad-Auflösung, uid-Lookup
# (+ name-Fallback nur für uid-lose Einträge, Launcher-Semantik), Feld-Passthrough
# (responsibility #7 / icon), mtime-Cache-Invalidierung, fehlende Datei = leer.
# Fixtures ausschließlich in mktemp -d — NIE die echte Registry anfassen.
set -uo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/_helper.sh"

MJS="$ENGINE_ROOT/dashboard/server/utils/registry.mjs"
FIX="$(mktemp -d)"
trap 'rm -rf "$FIX"' EXIT

cat > "$FIX/projects.registry.json" <<'JSON'
{
  "version": 1,
  "projects": [
    { "uid": "acme", "name": "acme-app", "label": "Acme App", "path": "/tmp/acme",
      "standup": "/tmp/acme/standup", "theme": "minimal", "status": "active",
      "responsibility": "Beispiel-Produkt — owns: app", "icon": "acme.png" },
    { "name": "legacy-proj", "path": "/tmp/legacy", "standup": "/tmp/legacy/standup" }
  ]
}
JSON

n() { node --input-type=module -e "import {registryPath, loadRegistry, listProjects, projectByUid} from 'file://$MJS'; const R='$FIX/projects.registry.json'; console.log($1)"; }

it "registryPath: NUXT_REGISTRY hat Vorrang"
eq "$(n "registryPath({NUXT_REGISTRY:'/x/reg.json'}, '/egal')")" "/x/reg.json"

it "registryPath: Default = tool-hub-Root neben der Engine (cwd/../..)"
eq "$(n "registryPath({}, '/hub/engine/dashboard')")" "/hub/projects.registry.json"

it "listProjects liefert beide Einträge"
eq "$(n "listProjects(R).length")" "2"

it "projectByUid: uid-Lookup trifft acme"
eq "$(n "projectByUid('acme', R).label")" "Acme App"

it "projectByUid: responsibility (#7) wird durchgereicht"
contains "$(n "projectByUid('acme', R).responsibility")" "owns: app"

it "projectByUid: icon-Feld wird durchgereicht"
eq "$(n "projectByUid('acme', R).icon")" "acme.png"

it "projectByUid: name-Fallback NUR für uid-lose Einträge"
eq "$(n "projectByUid('legacy-proj', R).path")" "/tmp/legacy"

it "projectByUid: name-Lookup greift NICHT, wenn der Eintrag eine uid hat"
eq "$(n "projectByUid('acme-app', R)")" "null"

it "projectByUid: unbekannte uid => null"
eq "$(n "projectByUid('gibtsnicht', R)")" "null"

it "fehlende Datei => leere projects (kein Crash)"
eq "$(n "loadRegistry('$FIX/fehlt.json').projects.length")" "0"

it "mtime-Cache: Änderung an der Datei wird ohne Neustart sichtbar"
out="$(node --input-type=module -e "
import {loadRegistry} from 'file://$MJS'
import {writeFileSync, utimesSync} from 'node:fs'
const R='$FIX/projects.registry.json'
const before = loadRegistry(R).projects.length
writeFileSync(R, JSON.stringify({version:1, projects:[{uid:'solo', name:'solo', path:'/tmp/s', standup:'/tmp/s'}]}))
const t = new Date(Date.now()+2000); utimesSync(R, t, t)   // mtime sicher != alt
const after = loadRegistry(R).projects.length
console.log(before + '->' + after)
")"
eq "$out" "2->1"

summary
