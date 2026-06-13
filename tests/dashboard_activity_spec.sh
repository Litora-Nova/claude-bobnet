#!/usr/bin/env bash
# tests/dashboard_activity_spec.sh — Black-Box-Spec gegen die dokumentierte
# Aktivitäts-Semantik (Issue #10 + Auflage "blocked bleibt prominent"):
#   working = busy ≤ workingMin · running = busy zwischen den Schwellen ·
#   idle = explizit idle/done ODER stale · registered = keine Logs (Projekt-Ebene) ·
#   blocked = letzter Beat blocked, altersUNabhängig (Sonderstatus).
# Aufruf der PURE functions in dashboard/server/utils/activity.mjs direkt via node.
set -uo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/_helper.sh"

MJS="$ENGINE_ROOT/dashboard/server/utils/activity.mjs"
NOW=1800000000000   # fixer Bezugspunkt (UTC ms) — Tests sind zeitunabhängig

n() { node --input-type=module -e "import {agentActivity, projectActivity, thresholdsFrom} from 'file://$MJS'; const NOW=$NOW, MIN=60000; console.log($1)"; }

# ── Agent-Ebene ──────────────────────────────────────────────────────────────
it "busy vor 5 min => working"
eq "$(n "agentActivity({status:'busy', epoch:NOW-5*MIN}, NOW)")" "working"

it "busy vor 30 min => running (zwischen den Schwellen)"
eq "$(n "agentActivity({status:'busy', epoch:NOW-30*MIN}, NOW)")" "running"

it "busy vor 120 min => idle (stale)"
eq "$(n "agentActivity({status:'busy', epoch:NOW-120*MIN}, NOW)")" "idle"

it "expliziter idle-Beat vor 5 min => idle (Issue-#10: idle = nur idle/stale)"
eq "$(n "agentActivity({status:'idle', epoch:NOW-5*MIN}, NOW)")" "idle"

it "done vor 5 min => idle"
eq "$(n "agentActivity({status:'done', epoch:NOW-5*MIN}, NOW)")" "idle"

it "blocked vor 500 min => blocked (sticky, altersunabhängig — Auflage)"
eq "$(n "agentActivity({status:'blocked', epoch:NOW-500*MIN}, NOW)")" "blocked"

it "kein Beat => idle"
eq "$(n "agentActivity(null, NOW)")" "idle"

it "Schwellen-Override greift (busy 30 min, workingMin=45 => working)"
eq "$(n "agentActivity({status:'busy', epoch:NOW-30*MIN}, NOW, {workingMin:45, runningMin:60})")" "working"

# ── Projekt-Rollup ───────────────────────────────────────────────────────────
it "ein working schlägt idle durch => working"
eq "$(n "projectActivity(['working','idle'])")" "working"

it "nur idle => idle"
eq "$(n "projectActivity(['idle','idle'])")" "idle"

it "blocked dominiert ALLES (Prominenz-Auflage)"
eq "$(n "projectActivity(['blocked','working','running'])")" "blocked"

it "keine Agents + keine Logs => registered"
eq "$(n "projectActivity([], {hasLogs:false})")" "registered"

it "keine Agents, aber Session-Probe => running (Opt-in tmux-Signal)"
eq "$(n "projectActivity([], {sessionPresent:true})")" "running"

it "nur idle, aber Session-Probe hebt auf running"
eq "$(n "projectActivity(['idle'], {sessionPresent:true})")" "running"

# ── Schwellen aus env ────────────────────────────────────────────────────────
it "thresholdsFrom: Defaults 10/60"
eq "$(n "JSON.stringify(thresholdsFrom({}))")" '{"workingMin":10,"runningMin":60}'

it "thresholdsFrom: env-Override + Müll fällt auf Default"
eq "$(n "JSON.stringify(thresholdsFrom({NUXT_ACTIVITY_WORKING_MIN:'15', NUXT_ACTIVITY_RUNNING_MIN:'quatsch'}))")" '{"workingMin":15,"runningMin":60}'

# ── Multiplexer-Probe-Helper (tmux→zellij-Port) ───────────────────────────────
# Drei NEUE pure Helper aus activity.mjs, gespiegelt aus scripts/lib/mux.sh.
# Eigener Importer m(): zieht resolveMuxBackend/muxListPlan/parseSessionList rein.
# has() ist die Probe-Funktion, die der echte Server reinreicht (Binary aufrufbar?);
# in den Tests simulieren wir sie als Closure über ein "vorhandene Binaries"-Set,
# damit die Helper OHNE echten Multiplexer prüfbar bleiben (pur).
m() { node --input-type=module -e "import {resolveMuxBackend, muxListPlan, parseSessionList} from 'file://$MJS'; const has=(set)=>(b)=>set.includes(b); console.log($1)"; }

# resolveMuxBackend — auto bevorzugt tmux (Rückwärtskompat)
it "resolveMuxBackend: auto + tmux vorhanden => tmux"
eq "$(m "resolveMuxBackend({BOBNET_MUX:'auto'}, has(['tmux','zellij']))")" "tmux"

it "resolveMuxBackend: auto OHNE tmux, mit zellij (PATH) => zellij"
eq "$(m "resolveMuxBackend({BOBNET_MUX:'auto'}, has(['zellij']))")" "zellij"

it "resolveMuxBackend: auto ohne tmux, zellij nur user-scope (~/.local/bin) => zellij"
eq "$(m "resolveMuxBackend({BOBNET_MUX:'auto', HOME:'/home/acme'}, has(['/home/acme/.local/bin/zellij']))")" "zellij"

it "resolveMuxBackend: Default (kein BOBNET_MUX) = auto-Verhalten, tmux bevorzugt"
eq "$(m "resolveMuxBackend({}, has(['tmux','zellij']))")" "tmux"

it "resolveMuxBackend: explizit tmux erzwungen (selbst wenn nur zellij da wäre)"
eq "$(m "resolveMuxBackend({BOBNET_MUX:'tmux'}, has(['zellij']))")" "tmux"

it "resolveMuxBackend: explizit zellij erzwungen (selbst wenn nur tmux da wäre)"
eq "$(m "resolveMuxBackend({BOBNET_MUX:'zellij'}, has(['tmux']))")" "zellij"

it "resolveMuxBackend: BOBNET_MUX case-insensitiv (AUTO => auto-Verhalten)"
eq "$(m "resolveMuxBackend({BOBNET_MUX:'AUTO'}, has(['zellij']))")" "zellij"

it "resolveMuxBackend: nichts verfügbar => fällt leise auf tmux-Plan (kein Signal)"
eq "$(m "resolveMuxBackend({BOBNET_MUX:'auto'}, has([]))")" "tmux"

# muxListPlan — list-Befehl + zu probierende Binaries je Backend
it "muxListPlan(tmux): bins=[tmux], args=ls -F session_name"
eq "$(m "JSON.stringify(muxListPlan('tmux', {}))")" '{"bins":["tmux"],"args":["ls","-F","#{session_name}"]}'

it "muxListPlan(zellij): bins inkl. \$HOME/.local/bin-Fallback, list-sessions --short"
eq "$(m "JSON.stringify(muxListPlan('zellij', {HOME:'/home/acme'}))")" '{"bins":["zellij","/home/acme/.local/bin/zellij"],"args":["list-sessions","--no-formatting","--short"]}'

it "muxListPlan(zellij) ohne HOME: nur 'zellij' (kein leerer Fallback-Pfad)"
eq "$(m "JSON.stringify(muxListPlan('zellij', {}))")" '{"bins":["zellij"],"args":["list-sessions","--no-formatting","--short"]}'

it "muxListPlan: unbekanntes Backend fällt auf tmux-Plan (Default)"
eq "$(m "JSON.stringify(muxListPlan('quatsch', {}))")" '{"bins":["tmux"],"args":["ls","-F","#{session_name}"]}'

# parseSessionList — Roh-Output -> normalisierte Session-Namen
it "parseSessionList: lowercased die Namen (case-insensitiver uid/name-Vergleich)"
eq "$(m "JSON.stringify(parseSessionList('Acme-Bob\nENGINE'))")" '["acme-bob","engine"]'

it "parseSessionList: leere Zeilen + reiner Whitespace fliegen raus"
eq "$(m "JSON.stringify(parseSessionList('acme\n\n   \nbob'))")" '["acme","bob"]'

it "parseSessionList: tote zellij-Session '(EXITED …)' wird verworfen"
eq "$(m "JSON.stringify(parseSessionList('acme\ndead (EXITED - 1m ago)\nbob'))")" '["acme","bob"]'

it "parseSessionList: lebende zellij-Session mit Status-Klammer => Suffix abgeschnitten"
eq "$(m "JSON.stringify(parseSessionList('acme (current)'))")" '["acme"]'

it "parseSessionList: EXITED case-insensitiv (exited) auch verworfen"
eq "$(m "JSON.stringify(parseSessionList('live\ngone (exited - 5s ago)'))")" '["live"]'

it "parseSessionList: leerer/undefined Input => leere Liste (kein Crash)"
eq "$(m "JSON.stringify(parseSessionList(undefined))")" '[]'

summary
