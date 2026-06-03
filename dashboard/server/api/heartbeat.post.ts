import { promises as fs } from 'node:fs'
import { resolve, join } from 'node:path'
import { AGENTS, GROUPS, PO } from '../utils/team'

// Der PO (oder jedes Mitglied) trägt seinen Status selbst übers Dashboard ein.
// Schreibt eine Heartbeat-Zeile in standup/<Agent>.log — gleiches Format wie standup/log.sh.
// Zusätzlich: @-Erwähnungen im Text (@team, @dev, @Name) werden in standup/_inbox.md
// gepusht, sodass die adressierten Agents sie beim Stand-up sehen.
// AGENTS/GROUPS/PO kommen aus der Team-Config (server/utils/team.ts), nicht mehr hardcoded.

export default defineEventHandler(async (event) => {
  const body = await readBody(event)
  const agent = String(body?.agent || PO).replace(/[^A-Za-z0-9_-]/g, '') || PO
  const status = ['busy', 'idle', 'blocked', 'done'].includes(body?.status) ? body.status : 'busy'
  const msg = String(body?.msg || '').replace(/[\r\n]+/g, ' ').trim().slice(0, 200)

  const cfg = useRuntimeConfig()
  const dir = resolve(process.cwd(), cfg.standupDir as string)
  // Europe/Berlin (Memory timezone-europe-berlin). sv-SE → "YYYY-MM-DD HH:MM:SS".
  const stamp = new Date().toLocaleString('sv-SE', { timeZone: 'Europe/Berlin', hour12: false })
  const logTs = stamp.slice(0, 16) // "YYYY-MM-DD HH:MM" — Format wie log.sh
  const ts = stamp.slice(11, 16)   // HH:MM für die Inbox-Zeile

  await fs.appendFile(join(dir, `${agent}.log`), `${logTs} | ${status} | ${msg}\n`)

  // @-Erwähnungen auflösen (Gruppen + Einzelnamen, case-insensitiv) → Team-Inbox
  const targets = new Set<string>()
  for (const m of msg.matchAll(/@(\w+)/g)) {
    const tok = m[1].toLowerCase()
    if (GROUPS[tok]) GROUPS[tok].forEach(a => targets.add(a))
    else { const hit = AGENTS.find(a => a.toLowerCase() === tok); if (hit) targets.add(hit) }
  }
  targets.delete(agent) // nicht an sich selbst
  const inboxMsg = msg.replace(/[|]/g, ' ').trim()
  for (const t of targets) {
    await fs.appendFile(join(dir, '_inbox.md'), `${ts} | @${t} | ${inboxMsg} — (${agent})\n`)
  }

  return { ok: true, notified: [...targets] }
})
