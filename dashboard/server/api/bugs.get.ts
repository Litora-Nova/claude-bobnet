import { promises as fs } from 'node:fs'
import { resolve, join } from 'node:path'
import { render } from '../utils/md'

// Rendert standup/_bugs.md (Produkt-Bug-/QM-Log von Acme Inc, Bob pflegt — Quelle:
// Austins Durchklick) als HTML. Read-only: das Dashboard fixt keine Bugs, es zeigt
// nur. `empty` signalisiert der Seite, dass die Datei fehlt/leer ist.
export default defineEventHandler(async () => {
  const cfg = useRuntimeConfig()
  const root = resolve(process.cwd(), cfg.standupDir as string)
  const raw = await fs.readFile(join(root, '_bugs.md'), 'utf8').catch(() => '')
  return { html: raw ? render(raw) : '', empty: !raw.trim() }
})
