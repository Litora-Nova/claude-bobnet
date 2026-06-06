import { promises as fs } from 'node:fs'
import { join } from 'node:path'
import { tenantOf } from '../utils/tenant'

// Markiert einen Blocker dauerhaft als von Austin erledigt → er verschwindet aus
// der Dringend-Liste, auch wenn der (schlafende) Agent nie ein neues "done" postet.
// Body: { agent, blocker }. Format: "Agent | blocker-text" in standup/_resolved.md.
export default defineEventHandler(async (event) => {
  const body = await readBody(event)
  const agent = String(body?.agent || '').replace(/[^A-Za-z0-9_-]/g, '')
  const blocker = String(body?.blocker || '').replace(/[\r\n|]+/g, ' ').trim().slice(0, 200)
  if (!agent || !blocker) return { ok: false }

  const dir = tenantOf(event).standupDir
  await fs.appendFile(join(dir, '_resolved.md'), `${agent} | ${blocker}\n`)
  return { ok: true }
})
