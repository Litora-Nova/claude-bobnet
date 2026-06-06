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
