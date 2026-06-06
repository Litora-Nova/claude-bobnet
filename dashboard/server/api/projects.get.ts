import { promises as fs } from 'node:fs'
import { join } from 'node:path'
import { execSync } from 'node:child_process'
import { listProjects } from '../utils/registry.mjs'
import { tenantFromProject } from '../utils/tenant'
import { teamOf } from '../utils/team'
import { agentActivity, projectActivity, thresholdsFrom } from '../utils/activity.mjs'

// Bobiverse-Übersicht (#9 + #10): ALLE registrierten Projekte aus der Registry,
// je Projekt der Aktivitäts-Status (registered/running/working/idle + blocked
// prominent) aus der Heartbeat-Frische plus die letzten Beats (Cross-Projekt-
// Heartbeat-View). Tenant-NEUTRAL: liefert die Flotte, nicht das aktive Projekt.
//
// Optionale tmux-Probe (NUXT_TMUX_PROBE=1, Opt-in): "Session läuft"-Signal über
// Session-Namen, die uid/name des Projekts enthalten (Heuristik, hebt den Status
// mindestens auf 'running'). Default AUS — heartbeat-only bleibt portabel.

type Beat = { ts: string; status: string; msg: string; epoch: number; agent: string }

// Parser konsistent zu standup.get.ts: "YYYY-MM-DD HH:MM | status | msg"
// (alt "HH:MM | …" → Datum aus mtime). epoch (UTC ms) ist der Sort-Key.
function parseLine(line: string, fileMtimeMs: number, agent: string): Beat {
  const [tsRaw, status, ...rest] = line.split('|').map(s => s.trim())
  const ts = tsRaw || ''
  let epoch = fileMtimeMs, disp = ts
  const iso = ts.match(/^(\d{4}-\d{2}-\d{2})[ T](\d{2}):(\d{2})$/)
  if (iso) {
    epoch = Date.UTC(+iso[1].slice(0, 4), +iso[1].slice(5, 7) - 1, +iso[1].slice(8, 10), +iso[2], +iso[3])
    disp = `${iso[2]}:${iso[3]}`
  } else {
    const hm = ts.match(/^(\d{2}):(\d{2})$/)
    if (hm) {
      const d = new Date(fileMtimeMs)
      epoch = Date.UTC(d.getUTCFullYear(), d.getUTCMonth(), d.getUTCDate(), +hm[1], +hm[2])
      if (epoch > fileMtimeMs + 60_000) epoch -= 86_400_000
    }
  }
  return { ts: disp, status: status || '', msg: rest.join(' | '), epoch, agent }
}

// tmux-Sessions EINMAL pro Request listen (nur bei aktivierter Probe).
function tmuxSessions(): string[] | null {
  if (process.env.NUXT_TMUX_PROBE !== '1') return null
  try {
    return execSync("tmux ls -F '#{session_name}'", { timeout: 2000 })
      .toString().split('\n').map(s => s.trim().toLowerCase()).filter(Boolean)
  } catch { return null }   // kein tmux/keine Sessions → kein Signal
}

export default defineEventHandler(async () => {
  const now = Date.now()
  const th = thresholdsFrom(process.env)
  const sessions = tmuxSessions()
  const BEATS_PER_PROJECT = 5

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
      const beats = lines.slice(-BEATS_PER_PROJECT).map(l => parseLine(l, stat?.mtimeMs ?? now, agent))
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
    }
    } catch { return null }   // kaputter Registry-Eintrag (ohne path/standup) → Flotte zeigt den Rest
  }))).filter((p): p is NonNullable<typeof p> => p !== null)

  // Prominenz-Sortierung (blocked zuerst — urgent-jump), Rest in Registry-Reihenfolge.
  const ORDER: Record<string, number> = { blocked: 0, working: 1, running: 2, idle: 3, registered: 4 }
  projects.sort((a, b) => (ORDER[a.activity] ?? 9) - (ORDER[b.activity] ?? 9))

  return { projects, probe: sessions !== null, updatedAt: new Date().toISOString() }
})
