import { promises as fs } from 'node:fs'
import { join } from 'node:path'
import { render } from '../utils/md'
import { tenantOf } from '../utils/tenant'

// Rendert standup/_bugs.md (Produkt-Bug-/QM-Log von Acme Inc, Bob pflegt — Quelle:
// Durchklick des PO) als HTML. Read-only: das Dashboard fixt keine Bugs, es zeigt
// nur. `empty` signalisiert der Seite, dass die Datei fehlt/leer ist.
export default defineEventHandler(async (event) => {
  const root = tenantOf(event).standupDir
  const raw = await fs.readFile(join(root, '_bugs.md'), 'utf8').catch(() => '')
  return { html: raw ? render(raw) : '', empty: !raw.trim() }
})
