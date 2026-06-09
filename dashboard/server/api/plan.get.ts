import { promises as fs } from 'node:fs'
import { join } from 'node:path'
import { render } from '../utils/md'
import { tenantOf } from '../utils/tenant'

// Rendert GOAL.md + ROADMAP.md aus dem Projekt-ROOT (nicht standup-Dir!) als HTML
// — sichtbare, vorgegebene Repo-Struktur wie README.md (PO-Entscheid #30). Read-only:
// das Dashboard zeigt nur. `empty` = Datei fehlt ODER nur Whitespace → die /plan-Seite
// zeigt dann den roten "GOAL fehlt"-Alert (kein Kompass → der Plan-Richter prüft dagegen).
// tenant-aware via tenantOf(event): projectRoot = Registry-`path` (Tenant-Modus) bzw.
// eine Ebene über standup (Env-Modus). Muster: bugs.get.ts / report.get.ts.
async function read(root: string, file: string) {
  const raw = await fs.readFile(join(root, file), 'utf8').catch(() => '')
  return { html: raw.trim() ? render(raw) : '', empty: !raw.trim() }
}

export default defineEventHandler(async (event) => {
  const root = tenantOf(event).projectRoot
  const [goal, roadmap] = await Promise.all([read(root, 'GOAL.md'), read(root, 'ROADMAP.md')])
  return { goal, roadmap }
})
