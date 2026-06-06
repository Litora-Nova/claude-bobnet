import { promises as fs } from 'node:fs'
import { join } from 'node:path'
import { tenantOf } from '../utils/tenant'
import { parseTail, teamTz } from '../utils/beats.mjs'

// Liefert die letzten N Heartbeats EINES Agents (standup/<agent>.log), neueste
// zuerst — für den Inbox-"Meine Page"-Index (Austins letzte 42). Die standup-API
// liefert nur die letzten 3 pro Agent; hier gibt's die volle (begrenzte) History.
// Zeilen-Parsing zentral in server/utils/beats.mjs (Team-Zeitzone, stale-Regel).

type Beat = { date: string; time: string; status: string; msg: string; epoch: number }

export default defineEventHandler(async (event) => {
  const q = getQuery(event)
  const agent = String(q.agent || 'Austin').replace(/[^A-Za-z0-9_-]/g, '') || 'Austin'
  const limit = Math.min(Math.max(parseInt(String(q.limit || '42'), 10) || 42, 1), 200)

  const dir = tenantOf(event).standupDir
  const path = join(dir, `${agent}.log`)
  const stat = await fs.stat(path).catch(() => null)
  const mtimeMs = stat?.mtimeMs ?? Date.now()
  const raw = await fs.readFile(path, 'utf8').catch(() => '')
  const lines = raw.split('\n').map(l => l.trim()).filter(Boolean)
  const beats: Beat[] = parseTail(lines, mtimeMs, { tz: teamTz(), limit })
    .reverse().map(p => ({ date: p.date, time: p.time, status: p.status, msg: p.msg, epoch: p.epoch }))
  return { agent, count: beats.length, beats }
})
