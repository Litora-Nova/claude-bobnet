import { promises as fs } from 'node:fs'
import { resolve, join } from 'node:path'

// Liefert die letzten N Heartbeats EINES Agents (standup/<agent>.log), neueste
// zuerst — für den Inbox-"Meine Page"-Index (Austins letzte 42). Die standup-API
// liefert nur die letzten 3 pro Agent; hier gibt's die volle (begrenzte) History.
// Parser konsistent zu standup.get.ts: zwei Formate (alt "HH:MM | …", neu
// "YYYY-MM-DD HH:MM | …"). epoch (UTC ms) ist der Sort-Key.

type Beat = { date: string; time: string; status: string; msg: string; epoch: number }

function parse(line: string, fileMtimeMs: number): Beat {
  const [tsRaw, status, ...rest] = line.split('|').map(s => s.trim())
  const ts = tsRaw || ''
  let epoch = fileMtimeMs, date = '', time = ts
  const iso = ts.match(/^(\d{4}-\d{2}-\d{2})[ T](\d{2}):(\d{2})$/)
  if (iso) {
    epoch = Date.UTC(+iso[1].slice(0, 4), +iso[1].slice(5, 7) - 1, +iso[1].slice(8, 10), +iso[2], +iso[3])
    date = iso[1]; time = `${iso[2]}:${iso[3]}`
  } else {
    const hm = ts.match(/^(\d{2}):(\d{2})$/)
    if (hm) {
      const d = new Date(fileMtimeMs)
      epoch = Date.UTC(d.getUTCFullYear(), d.getUTCMonth(), d.getUTCDate(), +hm[1], +hm[2])
      if (epoch > fileMtimeMs + 60_000) epoch -= 86_400_000
      time = ts
    }
  }
  return { date, time, status: status || '', msg: rest.join(' | '), epoch }
}

export default defineEventHandler(async (event) => {
  const q = getQuery(event)
  const agent = String(q.agent || 'Austin').replace(/[^A-Za-z0-9_-]/g, '') || 'Austin'
  const limit = Math.min(Math.max(parseInt(String(q.limit || '42'), 10) || 42, 1), 200)

  const cfg = useRuntimeConfig()
  const dir = resolve(process.cwd(), cfg.standupDir as string)
  const path = join(dir, `${agent}.log`)
  const stat = await fs.stat(path).catch(() => null)
  const mtimeMs = stat?.mtimeMs ?? Date.now()
  const raw = await fs.readFile(path, 'utf8').catch(() => '')
  const lines = raw.split('\n').map(l => l.trim()).filter(Boolean)
  const beats = lines.slice(-limit).reverse().map(l => parse(l, mtimeMs))
  return { agent, count: beats.length, beats }
})
