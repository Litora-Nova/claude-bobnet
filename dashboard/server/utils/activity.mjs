// Aktivitäts-Semantik (#10) — PURE functions, bewusst .mjs (kein TS): direkt per
// node testbar (tests/dashboard_activity_spec.sh), nitro importiert mjs problemlos.
//
// Vier-Stufen-Semantik aus Heartbeat-Frische (Issue #10):
//   working    = frischer busy-Heartbeat (≤ workingMin)
//   running    = irgendein Heartbeat ≤ runningMin (Session da, keine frische Arbeit)
//   idle       = nur idle/done oder stale
//   registered = Projekt bekannt, (noch) keine Logs        [nur Projekt-Ebene]
// SONDERSTATUS (Auflage Remote Bob): blocked aus dem LETZTEN Beat bleibt prominent
// und altersunabhängig — ein blockierter Agent bleibt blocked bis aufgelöst, er
// darf in der Vier-Stufen-Semantik nicht untergehen (urgent-jump wie bisher).
//
// Schwellen in Minuten, env-konfigurierbar (NUXT_ACTIVITY_WORKING_MIN/_RUNNING_MIN);
// die env-Auflösung passiert im Aufrufer (tenant-/projects-Layer), hier nur Werte.

export const DEFAULT_THRESHOLDS = { workingMin: 10, runningMin: 60 }

// Letzter Beat EINES Agents → Agent-Status.
// latest: { status, epoch } | null · nowMs: Jetzt (UTC ms) · th: Schwellen.
// 'idle' heißt: der Agent MELDET idle/done (explizit) ODER alles ist stale —
// exakt die Issue-#10-Lesart „idle = nur idle/stale". 'running' ist der
// busy-Beat zwischen den Schwellen (Session da, Arbeit nicht mehr frisch).
export function agentActivity(latest, nowMs, th = DEFAULT_THRESHOLDS) {
  if (!latest || !latest.epoch) return 'idle'
  if (latest.status === 'blocked') return 'blocked'            // sticky + prominent
  const ageMin = (nowMs - latest.epoch) / 60000
  if (ageMin > th.runningMin) return 'idle'                    // stale, egal welcher Status
  if (latest.status === 'busy') return ageMin <= th.workingMin ? 'working' : 'running'
  return 'idle'                                                // explizit idle/done gemeldet
}

// Agent-Stati eines Projekts → Projekt-Rollup (Prominenz-Reihenfolge).
// opts.hasLogs: es existieren Heartbeat-Logs · opts.sessionPresent: optionales
// externes Signal (tmux-Probe, Opt-in) — hebt mindestens auf 'running'.
export function projectActivity(agentStates, opts = {}) {
  const s = new Set(agentStates)
  if (s.has('blocked')) return 'blocked'
  if (s.has('working')) return 'working'
  if (s.has('running') || opts.sessionPresent) return 'running'
  if (opts.hasLogs || agentStates.length > 0) return 'idle'
  return 'registered'
}

// Schwellen aus env-artigem Objekt lesen (zentral, damit Aufrufer konsistent sind).
export function thresholdsFrom(env = {}) {
  const num = (v, d) => { const n = parseInt(String(v ?? ''), 10); return Number.isFinite(n) && n > 0 ? n : d }
  return {
    workingMin: num(env.NUXT_ACTIVITY_WORKING_MIN, DEFAULT_THRESHOLDS.workingMin),
    runningMin: num(env.NUXT_ACTIVITY_RUNNING_MIN, DEFAULT_THRESHOLDS.runningMin),
  }
}

// ---------------------------------------------------------------------------
// Multiplexer-Session-Probe (backend-neutral) — spiegelt scripts/lib/mux.sh
// im Node-Layer nach, weil das Dashboard mux.sh nicht sourcen kann.
//
// Backend-Wahl per BOBNET_MUX=tmux|zellij|auto (Default auto): auto = tmux falls
// vorhanden (Rückwärtskompat), sonst zellij. Pro Multiplexer EIN list-Befehl:
//   tmux   -> tmux ls -F '#{session_name}'
//   zellij -> zellij list-sessions --no-formatting --short  (+ ~/.local/bin-Fallback,
//             weil zellij oft user-scope liegt und im Node/Cron-PATH fehlt).
// ---------------------------------------------------------------------------

// Liefert den list-Befehl + die zu probierenden Binaries für ein Backend.
// Reine Funktion (kein Prozess) — so für tests/node ohne echten Multiplexer prüfbar.
export function muxListPlan(backend, env = {}) {
  const home = env.HOME || ''
  if (backend === 'zellij') {
    // 'zellij' (PATH) zuerst, dann der user-scope-Fallback.
    const bins = ['zellij']
    if (home) bins.push(`${home}/.local/bin/zellij`)
    return { bins, args: ['list-sessions', '--no-formatting', '--short'] }
  }
  // Default/tmux: das Bestehende.
  return { bins: ['tmux'], args: ['ls', '-F', '#{session_name}'] }
}

// Backend aus BOBNET_MUX auflösen. has(): "ist dieses Binary aufrufbar?" — der
// Aufrufer reicht eine Probe-Funktion rein (im Server: command-Existenz-Check),
// damit diese Datei pur/testbar bleibt. auto bevorzugt tmux (Rückwärtskompat).
export function resolveMuxBackend(env = {}, has = () => true) {
  const want = (env.BOBNET_MUX || 'auto').toLowerCase()
  const home = env.HOME || ''
  const tmuxOk = () => has('tmux')
  const zellijOk = () => has('zellij') || (home && has(`${home}/.local/bin/zellij`))
  if (want === 'tmux') return 'tmux'
  if (want === 'zellij') return 'zellij'
  // auto (oder Unbekanntes): tmux bevorzugt, sonst zellij.
  if (tmuxOk()) return 'tmux'
  if (zellijOk()) return 'zellij'
  return 'tmux'   // nichts da -> tmux-Plan, der Aufruf scheitert leise (kein Signal)
}

// Roh-Output einer Session-Liste -> normalisierte Session-Namen.
// zellij hängt bei toten Sessions einen Marker an (z. B. "name (EXITED - 1m ago)").
// EXITED-Zeilen sind KEINE laufende Session -> komplett raus (sonst gäbe die Probe
// ein falsches "running"). Bei lebenden zellij-Sessions schneiden wir einen evtl.
// vorhandenen runden Status-Klammer-Suffix ab. Namen lowercased, damit der
// uid/name-Vergleich case-insensitiv bleibt (wie zuvor bei tmux).
export function parseSessionList(raw) {
  return String(raw ?? '')
    .split('\n')
    .map(s => s.trim())
    .filter(s => s && !/\(\s*EXITED/i.test(s))   // tote zellij-Sessions verwerfen
    .map(s => s.replace(/\s*\(.*\)\s*$/, '').trim().toLowerCase())  // Status-Suffix abschneiden
    .filter(Boolean)
}
