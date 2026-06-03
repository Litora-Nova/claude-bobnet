import { promises as fs } from 'node:fs'
import { resolve, join } from 'node:path'
import { TEAM, RETIRED, categoryOf, parentOf } from '../utils/team'
import type { Category } from '../utils/team'
import { displayNameOf, bioOf, themeMeta } from '../utils/theme'
import { render } from '../utils/md'

type Beat = { ts: string; status: string; msg: string; epoch: number }
type Agent = { name: string; id?: string; displayName?: string; bio?: string; external?: boolean; category?: Category; parent?: string | null; role: string; order: number; latest: Beat | null; history: Beat[] }

// Akzeptiert zwei Formate (Wechsel 28.05. wg. sort-Bug):
//   alt:  "HH:MM | status | msg"            → Datum aus mtime der Datei
//   neu:  "YYYY-MM-DD HH:MM | status | msg" → Datum direkt aus dem Eintrag
// `ts` bleibt für die Anzeige die HH:MM-Form; `epoch` (UTC ms) ist der echte
// Sort-Key. Für ältere History-Zeilen ohne Datum ist epoch nur grob (mtime
// der Datei), aber das ist Anzeige — sortiert wird auf `latest.epoch`.
function parseLine(line: string, fileMtimeMs: number): Beat {
  const [tsRaw, status, ...rest] = line.split('|').map(s => s.trim())
  const ts = tsRaw || ''
  let epoch = fileMtimeMs
  // ISO-Form?
  const iso = ts.match(/^(\d{4}-\d{2}-\d{2})[ T](\d{2}):(\d{2})$/)
  if (iso) {
    epoch = Date.UTC(+iso[1].slice(0, 4), +iso[1].slice(5, 7) - 1, +iso[1].slice(8, 10), +iso[2], +iso[3])
  } else {
    // alt: HH:MM — Datum aus mtime nehmen, Uhrzeit aus Eintrag.
    const hm = ts.match(/^(\d{2}):(\d{2})$/)
    if (hm) {
      const d = new Date(fileMtimeMs)
      epoch = Date.UTC(d.getUTCFullYear(), d.getUTCMonth(), d.getUTCDate(), +hm[1], +hm[2])
      // Wenn die zusammengesetzte Zeit > mtime ist, ist sie wahrscheinlich
      // vom Vortag (Heartbeat um 23:59, mtime jetzt 00:05 nächsten Tag).
      if (epoch > fileMtimeMs + 60_000) epoch -= 86_400_000
    }
  }
  return { ts, status: status || '', msg: rest.join(' | '), epoch }
}

// Anzeige-Form fürs Frontend: bei ISO-Datum nur die Uhrzeit zeigen
// (Kompatibilität zur bestehenden UI, die `HH:MM` erwartet).
function displayTs(ts: string): string {
  const iso = ts.match(/^\d{4}-\d{2}-\d{2}[ T](\d{2}:\d{2})$/)
  return iso ? iso[1] : ts
}

export default defineEventHandler(async () => {
  const cfg = useRuntimeConfig()
  const dir = resolve(process.cwd(), cfg.standupDir as string)

  let files: string[] = []
  try { files = await fs.readdir(dir) } catch { /* Ordner fehlt noch */ }

  const agents: Agent[] = []
  for (const f of files.filter(f => f.endsWith('.log'))) {
    const name = f.replace(/\.log$/, '')
    if (RETIRED.has(name)) continue
    if (name === 'releases') continue          // Bender-Release-Logbuch, kein Agent
    const path = join(dir, f)
    const stat = await fs.stat(path).catch(() => null)
    const mtimeMs = stat?.mtimeMs ?? Date.now()
    const raw = await fs.readFile(path, 'utf8').catch(() => '')
    const lines = raw.split('\n').map(l => l.trim()).filter(Boolean)
    const last3 = lines.slice(-3).reverse().map(l => parseLine(l, mtimeMs))
    // ts auf HH:MM normalisieren (kompatibel zur bestehenden UI).
    for (const b of last3) b.ts = displayTs(b.ts)
    const meta = TEAM[name] || { role: '', order: 99 }
    agents.push({ name, role: meta.role, order: meta.order, latest: last3[0] || null, history: last3 })
  }
  // Roster-Mitglieder ohne Log trotzdem zeigen — mit zwei Sonderfällen:
  //   - Externe (Tim/Henry, eigener Claude-Kontext, kein Heartbeat-Log):
  //     nur zeigen, wenn ihre Channel-Datei kürzlich angefasst wurde
  //     (≤ 48 h = "aktiv connected"). Pseudo-Heartbeat aus mtime.
  //   - Interne ohne Log: leeres Card wie bisher.
  const EXT_FRESH_MS = 48 * 60 * 60 * 1000
  for (const [name, meta] of Object.entries(TEAM)) {
    if (agents.some(a => a.name === name)) continue
    if (meta.external && meta.channel) {
      const chPath = resolve(process.cwd(), meta.channel)
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
    a.displayName = displayNameOf(a.name)
    a.bio = bioOf(a.name)
    a.external = !!TEAM[a.name]?.external
    a.id = TEAM[a.name]?.id                 // stabiler Join-Key (Helfer-Icon-Wahl, Theme-Debug)
    a.category = categoryOf(a.name)        // bob | service | coworker | helper | human
    a.parent = parentOf(a.name)            // Eltern-Agent (nur Helfer), sonst null
  }
  agents.sort((a, b) => a.order - b.order)

  let sprint = ''
  try { sprint = await fs.readFile(join(dir, '_sprint.md'), 'utf8') } catch { /* optional */ }
  // sprintHtml = serverseitig gerenderter Markdown (Austin 2026-05-30 03:xx:
  // "unten der Sprint, der könnte noch HTML formatiert werden"). Reuse vom
  // gleichen md.render() den auch Briefing/Wünsche/Feedback/Reports nutzen —
  // konsistente Listen/Headings/Code-Spans im "md"-CSS-Block.
  const sprintHtml = sprint ? render(sprint) : ''

  return { agents, theme: themeMeta(), sprint, sprintHtml, updatedAt: new Date().toISOString() }
})
