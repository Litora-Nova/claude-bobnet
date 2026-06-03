import { promises as fs } from 'node:fs'
import { resolve, join } from 'node:path'

// Liest Austins Task-Liste (standup/austin.tasks.md) + die erledigten Blocker
// (standup/_resolved.md). Task-Format: "- [ ] @Bill Text" → owner=Bill (optional).
// Drei Zustände: "[ ]" offen → "[~]" mach ich grad → "[x]" fertig.
export default defineEventHandler(async () => {
  const cfg = useRuntimeConfig()
  const dir = resolve(process.cwd(), cfg.standupDir as string)

  const raw = await fs.readFile(join(dir, 'austin.tasks.md'), 'utf8').catch(() => '')
  const tasks = raw.split('\n')
    .map(l => l.match(/^\s*-\s*\[( |~|x|X)\]\s+(.*)$/))
    .filter((m): m is RegExpMatchArray => !!m)
    .map((m, id) => {
      let text = m[2].trim(), owner = ''
      const o = text.match(/^@(\w+)\s+(.*)$/)
      if (o) { owner = o[1]; text = o[2].trim() }
      const mark = m[1].toLowerCase()
      const state = mark === 'x' ? 'done' : mark === '~' ? 'doing' : 'open'
      return { id, state, done: state === 'done', text, owner }
    })

  // Von Austin erledigte Blocker (agent|text) → die filtert das Dashboard aus der
  // Dringend-Liste raus, damit ein schlafender Agent nicht ewig „blocked" bleibt.
  const resolvedRaw = await fs.readFile(join(dir, '_resolved.md'), 'utf8').catch(() => '')
  const resolved = resolvedRaw.split('\n').map(l => l.trim()).filter(Boolean).map(line => {
    const [agent, ...rest] = line.split('|').map(s => s.trim())
    return `${agent}|${rest.join(' | ')}`
  })

  return { tasks, resolved }
})
