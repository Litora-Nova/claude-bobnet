import { promises as fs } from 'node:fs'
import { join } from 'node:path'
import { execSync } from 'node:child_process'
import { listProjects } from '../utils/registry.mjs'
import { tenantFromProject } from '../utils/tenant'
import { teamOf } from '../utils/team'
import { agentActivity, projectActivity, thresholdsFrom, resolveMuxBackend, muxListPlan, parseSessionList } from '../utils/activity.mjs'
import { parseTail, teamTz } from '../utils/beats.mjs'

// Bobiverse-Übersicht (#9 + #10): ALLE registrierten Projekte aus der Registry,
// je Projekt der Aktivitäts-Status (registered/running/working/idle + blocked
// prominent) aus der Heartbeat-Frische plus die letzten Beats (Cross-Projekt-
// Heartbeat-View). Tenant-NEUTRAL: liefert die Flotte, nicht das aktive Projekt.
//
// Optionale Multiplexer-Session-Probe (NUXT_TMUX_PROBE=1, Opt-in): "Session
// läuft"-Signal über Session-Namen, die uid/name des Projekts enthalten
// (Heuristik, hebt den Status mindestens auf 'running'). Default AUS — heartbeat-
// only bleibt portabel. Welcher Multiplexer abgefragt wird, entscheidet
// BOBNET_MUX=tmux|zellij|auto (Default auto: tmux falls vorhanden, sonst zellij)
// — dieselbe Logik wie scripts/lib/mux.sh, hier im Node-Layer nachgebildet
// (das Dashboard kann mux.sh nicht sourcen). Helper liegen in utils/activity.mjs.

type Beat = { ts: string; status: string; msg: string; epoch: number; agent: string }
// Zeilen-Parsing zentral in server/utils/beats.mjs: ISO-Stamps über die
// Team-Zeitzone (DEV_TEAM_TZ), datumslose Alt-Zeilen nur als LETZTE Zeile
// mtime-geankert, sonst stale (epoch 0 → sinkt im Sort, nie „frisch").

// "Ist dieses Binary aufrufbar?" — leiser command-Existenz-Check (kein Fehler,
// nur true/false), damit resolveMuxBackend pur bleiben kann. Absolute Pfade
// (z. B. ~/.local/bin/zellij) werden direkt getestet.
function hasBin(bin: string): boolean {
  try {
    if (bin.includes('/')) { execSync(`test -x ${JSON.stringify(bin)}`, { timeout: 1000 }); return true }
    execSync(`command -v ${JSON.stringify(bin)}`, { timeout: 1000, stdio: 'ignore' }); return true
  } catch { return false }
}

// Multiplexer-Sessions EINMAL pro Request listen (nur bei aktivierter Probe),
// backend-neutral via BOBNET_MUX. Probiert die Binaries des gewählten Backends
// der Reihe nach (zellij: PATH, dann ~/.local/bin-Fallback) — erstes, das eine
// Liste liefert, gewinnt. Kein Multiplexer/keine Sessions → null (kein Signal).
function muxSessions(): string[] | null {
  if (process.env.NUXT_TMUX_PROBE !== '1') return null
  const backend = resolveMuxBackend(process.env, hasBin)
  const { bins, args } = muxListPlan(backend, process.env)
  for (const bin of bins) {
    try {
      const out = execSync([bin, ...args].map(a => JSON.stringify(a)).join(' '), { timeout: 2000 }).toString()
      return parseSessionList(out)
    } catch { /* nächstes Binary probieren */ }
  }
  return null
}

export default defineEventHandler(async () => {
  const now = Date.now()
  const th = thresholdsFrom(process.env)
  const tz = teamTz()
  const sessions = muxSessions()
  const BEATS_PER_PROJECT = 3   // #29: PO — 5 war zu viel, 3 reicht in der Übersicht

  const projects = (await Promise.all(listProjects().map(async (p: any) => {
    try {
    const tenant = tenantFromProject(p)
    const team = teamOf(tenant)

    let files: string[] = []
    try { files = await fs.readdir(tenant.standupDir) } catch { /* standup fehlt noch */ }
    const logs = files.filter(f => f.endsWith('.log'))
      .filter(f => f !== 'releases.log' && !team.RETIRED.has(f.replace(/\.log$/, '')))

    const latestByAgent: Beat[] = []
    const recent: Beat[] = []
    for (const f of logs) {
      const agent = f.replace(/\.log$/, '')
      const path = join(tenant.standupDir, f)
      const stat = await fs.stat(path).catch(() => null)
      const raw = await fs.readFile(path, 'utf8').catch(() => '')
      const lines = raw.split('\n').map(l => l.trim()).filter(Boolean)
      if (!lines.length) continue
      const beats: Beat[] = parseTail(lines, stat?.mtimeMs ?? now, { tz, limit: BEATS_PER_PROJECT })
        .map(p => ({ ts: p.time, status: p.status, msg: p.msg, epoch: p.epoch, agent }))
      latestByAgent.push(beats[beats.length - 1])
      recent.push(...beats)
    }
    recent.sort((a, b) => b.epoch - a.epoch)

    const uidLc = String(p.uid || '').toLowerCase(), nameLc = String(p.name || '').toLowerCase()
    const sessionPresent = sessions
      ? sessions.some(s => (uidLc && s.includes(uidLc)) || (nameLc && s.includes(nameLc)))
      : undefined

    const agentStates = latestByAgent.map(b => agentActivity(b, now, th))
    const activity = projectActivity(agentStates, { hasLogs: logs.length > 0, sessionPresent })

    return {
      uid: p.uid || p.name,
      name: p.name,
      label: p.label || p.name,
      title: team.config.title || p.label || p.name,   // Titel-Switch pro Tenant
      po: team.PO,
      theme: p.theme || team.config.theme || 'bobiverse',
      status: p.status || '',                          // Registry-Status (active/…)
      responsibility: p.responsibility || '',          // #7
      icon: p.icon || '',                              // Web-URL/-Pfad; sonst Label-Fallback
      activity,                                        // registered|running|working|idle|blocked
      agents: latestByAgent.map(b => ({ agent: b.agent, status: b.status, ts: b.ts, state: agentActivity(b, now, th) })),
      recentBeats: recent.slice(0, BEATS_PER_PROJECT), // Cross-Projekt-Heartbeat-View
      latestBeatEpoch: recent[0]?.epoch ?? 0,          // #29: jüngster Beat → Aktualitäts-Sort
    }
    } catch { return null }   // kaputter Registry-Eintrag (ohne path/standup) → Flotte zeigt den Rest
  }))).filter((p): p is NonNullable<typeof p> => p !== null)

  // Aktualitäts-Sortierung (#29, PO): blocked-Projekte bleiben prominent zuerst
  // (urgent-jump, Auflage C), DANN alle übrigen nach jüngstem Beat absteigend
  // (neueste Aktivität oben). Sort-Key ~ (blocked ? 0 : 1, -latestBeatEpoch).
  projects.sort((a, b) => {
    const ba = a.activity === 'blocked' ? 0 : 1, bb = b.activity === 'blocked' ? 0 : 1
    if (ba !== bb) return ba - bb
    return (b.latestBeatEpoch ?? 0) - (a.latestBeatEpoch ?? 0)
  })

  return { projects, probe: sessions !== null, updatedAt: new Date().toISOString() }
})
