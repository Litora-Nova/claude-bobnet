import { promises as fs } from 'node:fs'
import { join } from 'node:path'
import { tenantOf } from '../utils/tenant'

// Nachricht ans Team: hängt eine Zeile an standup/_inbox.md an.
// Body: { agent, msg }. Format: "HH:MM | @Agent | msg" (UTC).
// Den Inbox liest das Team beim Stand-up-Start (siehe TEAM.md).
export default defineEventHandler(async (event) => {
  const body = await readBody(event)
  const agent = String(body?.agent || '').replace(/[^A-Za-z0-9_-]/g, '')
  const msg = String(body?.msg || '').replace(/[\r\n|]+/g, ' ').trim().slice(0, 200)
  if (!agent || !msg) return { ok: false }

  const dir = tenantOf(event).standupDir
  const ts = new Date().toISOString().slice(11, 16)
  await fs.appendFile(join(dir, '_inbox.md'), `${ts} | @${agent} | ${msg}\n`)
  return { ok: true }
})
