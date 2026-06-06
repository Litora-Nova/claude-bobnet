import { promises as fs } from 'node:fs'
import { join } from 'node:path'
import { tenantOf } from '../utils/tenant'

// Liest den Team-Inbox (standup/_inbox.md) und liefert die letzten Zeilen.
// Format pro Zeile: "HH:MM | @Agent | msg" (siehe notify.post.ts).
export default defineEventHandler(async (event) => {
  const dir = tenantOf(event).standupDir

  const raw = await fs.readFile(join(dir, '_inbox.md'), 'utf8').catch(() => '')
  const items = raw.split('\n').map(l => l.trim()).filter(Boolean).map((line, id) => {
    const [ts, target, ...rest] = line.split('|').map(s => s.trim())
    return { id, ts, target, msg: rest.join(' | ') }
  })
  // Neueste zuerst, auf die letzten 12 begrenzt (token-/render-arm).
  return { items: items.slice(-12).reverse() }
})
