import { promises as fs } from 'node:fs'
import { resolve, join } from 'node:path'

// Austins Tasks bearbeiten: { action: 'toggle'|'remove', id } | { action: 'add', text }
// Schreibt zurück nach standup/austin.tasks.md (Checkbox-Format bleibt erhalten).
// toggle schaltet zyklisch durch die drei Zustände: "[ ]" → "[~]" → "[x]" → "[ ]".
export default defineEventHandler(async (event) => {
  const body = await readBody(event)
  const cfg = useRuntimeConfig()
  const dir = resolve(process.cwd(), cfg.standupDir as string)
  const path = join(dir, 'austin.tasks.md')
  const raw = await fs.readFile(path, 'utf8').catch(() => '# Austins Tasks (Product Owner)\n')

  const lines = raw.split('\n')
  const taskRe = /^(\s*-\s*)\[( |~|x|X)\](\s+.*)$/
  const NEXT: Record<string, string> = { ' ': '~', '~': 'x', x: ' ' }

  if (body?.action === 'toggle' || body?.action === 'remove') {
    let idx = -1
    for (let i = 0; i < lines.length; i++) {
      const m = lines[i].match(taskRe)
      if (!m) continue
      idx++
      if (idx === Number(body.id)) {
        if (body.action === 'remove') { lines.splice(i, 1) }
        else { const cur = m[2].toLowerCase(); lines[i] = `${m[1]}[${NEXT[cur] ?? '~'}]${m[3]}` }
        break
      }
    }
  } else if (body?.action === 'add') {
    const text = String(body.text || '').replace(/[\r\n]+/g, ' ').trim().slice(0, 200)
    const exists = lines.some(l => { const m = l.match(taskRe); return m && m[3].trim() === text })
    if (text && !exists) {
      while (lines.length && !lines[lines.length - 1].trim()) lines.pop()
      lines.push(`- [ ] ${text}`)
    }
  }

  await fs.writeFile(path, lines.join('\n').replace(/\n*$/, '\n'))
  return { ok: true }
})
