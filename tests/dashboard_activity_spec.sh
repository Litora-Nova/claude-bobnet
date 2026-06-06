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

summary
