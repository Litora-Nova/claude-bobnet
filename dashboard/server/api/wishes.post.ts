import { promises as fs } from 'node:fs'
import { join } from 'node:path'
import { tenantOf } from '../utils/tenant'
import { frontmatter } from '../utils/md'

// Wünsche schreiben:
//   { action: 'add', author, target, priority, title, body }
//   { action: 'toggle-status', file }   // zyklisch open→in_progress→done→dropped→open
//   { action: 'update', file, body }    // ersetzt Body, Frontmatter bleibt
// Audit via git-blame — keine history-Liste im Frontmatter.

const STATUS_NEXT: Record<string, string> = {
  open: 'in_progress',
  in_progress: 'done',
  done: 'dropped',
  dropped: 'open',
}

const slug = (s: string) =>
  s.toLowerCase()
    .replace(/[äöüß]/g, c => ({ ä: 'ae', ö: 'oe', ü: 'ue', ß: 'ss' }[c] || c))
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-+|-+$/g, '')
    .slice(0, 60) || 'wunsch'

const today = () => new Date().toISOString().slice(0, 10)

function compose(d: Record<string, string>, title: string, body: string): string {
  const fm = `---
author: ${d.author || ''}
target: ${d.target || ''}
status: ${d.status || 'open'}
priority: ${d.priority || 'med'}
created: ${d.created || today()}
---

# Wunsch · ${title}

${body.trim()}
`
  return fm
}

export default defineEventHandler(async (event) => {
  const body = await readBody(event)
  const dir = join(tenantOf(event).standupDir, 'wishes')
  await fs.mkdir(dir, { recursive: true })

  if (body?.action === 'add') {
    const author = String(body.author || '').trim() || 'Anon'
    const target = String(body.target || '').trim() || 'team'
    const priority = (['low', 'med', 'high'].includes(body.priority) ? body.priority : 'med') as string
    const title = String(body.title || '').trim().slice(0, 120) || 'Unbenannt'
    const text = String(body.body || '').trim().slice(0, 5000)
    const created = today()
    const file = `${created}-${slug(title)}.md`
    const path = join(dir, file)
    // Existiert schon? Datei deduplizieren mit numerischem Suffix.
    let final = path, n = 2
    while (await fs.stat(final).then(() => true).catch(() => false)) {
      final = path.replace(/\.md$/, `-${n}.md`); n++
    }
    await fs.writeFile(final, compose({ author, target, status: 'open', priority, created }, title, text))
    return { ok: true, file: final.split('/').pop() }
  }

  if (body?.action === 'toggle-status') {
    const file = String(body.file || '')
    if (!/^[\w.-]+\.md$/.test(file)) return { ok: false, error: 'invalid file' }
    const path = join(dir, file)
    const raw = await fs.readFile(path, 'utf8').catch(() => '')
    if (!raw) return { ok: false, error: 'not found' }
    const { data, body: md } = frontmatter(raw)
    const cur = data.status || 'open'
    const next = STATUS_NEXT[cur] || 'open'
    // Body wieder über Composer schreiben — Title vom ersten # extrahieren.
    const titleM = md.match(/^#\s+(.+)$/m)
    const title = titleM ? titleM[1].replace(/^Wunsch\s*·\s*/i, '').trim() : 'Unbenannt'
    const rest = md.replace(/^#\s+.+\n?/m, '').trim()
    await fs.writeFile(path, compose({ ...data, status: next }, title, rest))
    return { ok: true, status: next }
  }

  if (body?.action === 'update') {
    const file = String(body.file || '')
    if (!/^[\w.-]+\.md$/.test(file)) return { ok: false, error: 'invalid file' }
    const path = join(dir, file)
    const raw = await fs.readFile(path, 'utf8').catch(() => '')
    if (!raw) return { ok: false, error: 'not found' }
    const { data, body: md } = frontmatter(raw)
    const titleM = md.match(/^#\s+(.+)$/m)
    const title = titleM ? titleM[1].replace(/^Wunsch\s*·\s*/i, '').trim() : 'Unbenannt'
    const text = String(body.body || '').trim().slice(0, 5000)
    await fs.writeFile(path, compose(data, title, text))
    return { ok: true }
  }

  return { ok: false, error: 'unknown action' }
})
