import { promises as fs } from 'node:fs'
import { resolve, join } from 'node:path'
import { tenantOf } from '../utils/tenant'
import { teamOf } from '../utils/team'
import type { Category } from '../utils/team'
import { themeOf } from '../utils/theme'
import { parseTail, teamTz } from '../utils/beats.mjs'
import { render } from '../utils/md'

type Beat = { ts: string; status: string; msg: string; epoch: number }
type Agent = { name: string; id?: string; displayName?: string; bio?: string; external?: boolean; category?: Category; parent?: string | null; role: string; order: number; latest: Beat | null; history: Beat[] }

// Zeilen-Parsing zentral in server/utils/beats.mjs (geteilt mit heartbeats/
// projects): ISO-Stamps über die Team-Zeitzone (DEV_TEAM_TZ), datumslose
// Alt-Zeilen nur als LETZTE Zeile mtime-geankert, sonst stale — siehe dort.

export default defineEventHandler(async (event) => {
  const tenant = tenantOf(event)
  const team = teamOf(tenant)
  const theme = themeOf(tenant, team)
  const tz = teamTz()
  const dir = tenant.standupDir

  let files: string[] = []
  try { files = await fs.readdir(dir) } catch { /* Ordner fehlt noch */ }

  const agents: Agent[] = []
  for (const f of files.filter(f => f.endsWith('.log'))) {
    const name = f.replace(/\.log$/, '')
    if (team.RETIRED.has(name)) continue
    if (name === 'releases') continue          // Bender-Release-Logbuch, kein Agent
    const path = join(dir, f)
    const stat = await fs.stat(path).catch(() => null)
    const mtimeMs = stat?.mtimeMs ?? Date.now()
    const raw = await fs.readFile(path, 'utf8').catch(() => '')
    const lines = raw.split('\n').map(l => l.trim()).filter(Boolean)
    // ts = HH:MM-Anzeigeform (kompatibel zur bestehenden UI), epoch = Sort-Key.
    const last3: Beat[] = parseTail(lines, mtimeMs, { tz, limit: 3 })
      .reverse().map(p => ({ ts: p.time, status: p.status, msg: p.msg, epoch: p.epoch }))
    // name = Log-Dateiname = uid ODER Persona-Name → Member per beidem auflösen.
    const meta = team.memberOf(name) || { role: '', order: 99 }
    agents.push({ name, role: meta.role, order: meta.order, latest: last3[0] || null, history: last3 })
  }
  // Roster-Mitglieder ohne Log trotzdem zeigen — mit zwei Sonderfällen:
  //   - Externe (Tim/Henry, eigener Claude-Kontext, kein Heartbeat-Log):
  //     nur zeigen, wenn ihre Channel-Datei kürzlich angefasst wurde
  //     (≤ 48 h = "aktiv connected"). Pseudo-Heartbeat aus mtime.
  //   - Interne ohne Log: leeres Card wie bisher.
  const EXT_FRESH_MS = 48 * 60 * 60 * 1000
  for (const [name, meta] of Object.entries(team.TEAM)) {
    // Schon als Log-Karte da? Match auf Persona-Namen ODER Log-Key (uid) — sonst
    // erschiene der uid-geloggte Member (bobnet-infra.log) zusaetzlich als leere Persona-Karte.
    if (agents.some(a => a.name === name || (meta.uid && a.name === meta.uid))) continue
    if (meta.external && meta.channel) {
      // Channel-Pfad: Tenant-Modus relativ zum standup-Dir des Projekts; Env-Modus
      // wie bisher relativ zum App-cwd (backward-kompatibel zu Alt-Configs).
      const chPath = resolve(tenant.uid ? tenant.standupDir : process.cwd(), meta.channel)
      const st = await fs.stat(chPath).catch(() => null)
      if (!st) continue                            // Datei weg → nicht zeigen
      const age = Date.now() - st.mtimeMs
      if (age > EXT_FRESH_MS) continue             // alt → nicht zeigen
      const d = new Date(st.mtimeMs)
      const hm = `${String(d.getHours()).padStart(2, '0')}:${String(d.getMinutes()).padStart(2, '0')}`
      const ago = age < 3600_000
        ? `vor ${Math.round(age / 60_000)} min`
        : `vor ${Math.round(age / 3600_000)} h`
      const beat: Beat = { ts: hm, status: 'idle', msg: `extern · Channel ${ago} aktualisiert`, epoch: st.mtimeMs }
      agents.push({ name, role: meta.role, order: meta.order, latest: beat, history: [beat] })
      continue
    }
    agents.push({ name, role: meta.role, order: meta.order, latest: null, history: [] })
  }
  // Theme-Enrichment (Schicht ②): Anzeigename/Emoji/Bio aus dem aktiven Theme,
  // gekeyt auf den stabilen Roster-Namen. `name` bleibt der Routing-/Log-Key.
  for (const a of agents) {
    a.displayName = theme.displayNameOf(a.name)
    a.bio = theme.bioOf(a.name)
    a.external = !!team.memberOf(a.name)?.external
    a.id = team.memberOf(a.name)?.id        // stabiler Join-Key (Helfer-Icon-Wahl, Theme-Debug)
    a.category = team.categoryOf(a.name)    // bob | service | coworker | helper | human
    a.parent = team.parentOf(a.name)        // Eltern-Agent (nur Helfer), sonst null
  }
  agents.sort((a, b) => a.order - b.order)

  let sprint = ''
  try { sprint = await fs.readFile(join(dir, '_sprint.md'), 'utf8') } catch { /* optional */ }
  // sprintHtml = serverseitig gerenderter Markdown (PO 2026-05-30 03:xx:
  // "unten der Sprint, der könnte noch HTML formatiert werden"). Reuse vom
  // gleichen md.render() den auch Briefing/Wünsche/Feedback/Reports nutzen —
  // konsistente Listen/Headings/Code-Spans im "md"-CSS-Block.
  const sprintHtml = sprint ? render(sprint) : ''

  return { agents, theme: theme.meta, sprint, sprintHtml, updatedAt: new Date().toISOString() }
})
