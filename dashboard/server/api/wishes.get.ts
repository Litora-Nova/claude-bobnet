import { promises as fs } from 'node:fs'
import { resolve, join } from 'node:path'
import { render, frontmatter } from '../utils/md'
import { roleOf } from '../utils/team'

// Liest Wünsche (standup/wishes/YYYY-MM-DD-<slug>.md, Frontmatter
// author/target/status/priority/created — siehe standup/wishes/README.md).
//
// Ohne ?file: Liste (sortiert nach priority desc, created desc).
// Mit  ?file=<name>.md: zusätzlich `current` mit Frontmatter + gerendertem Body-HTML.

type WishMeta = {
  file: string
  title: string
  author: string
  authorRole: string
  target: string
  targetRole: string
  status: 'open' | 'in_progress' | 'done' | 'dropped' | string
  priority: 'low' | 'med' | 'high' | string
  created: string
}

const PRIO_RANK: Record<string, number> = { high: 3, med: 2, low: 1 }

// Erste # Überschrift als Titel; sonst Filename (ohne .md).
function titleOf(body: string, file: string): string {
  const m = body.match(/^#\s+(.+)$/m)
  return m ? m[1].replace(/^Wunsch\s*·\s*/i, '').trim() : file.replace(/\.md$/, '')
}

function meta(raw: string, file: string): WishMeta {
  const { data, body } = frontmatter(raw)
  const author = data.author || ''
  const target = data.target || ''
  return {
    file,
    title: titleOf(body, file),
    author,
    authorRole: roleOf(author),
    target,
    targetRole: roleOf(target),  // '' wenn target='team' o. ä.
    status: (data.status || 'open') as WishMeta['status'],
    priority: (data.priority || 'med') as WishMeta['priority'],
    created: data.created || file.slice(0, 10),
  }
}

export default defineEventHandler(async (event) => {
  const cfg = useRuntimeConfig()
  const root = resolve(process.cwd(), cfg.standupDir as string)
  const dir = join(root, 'wishes')

  let files: string[] = []
  try { files = await fs.readdir(dir) } catch { /* Ordner fehlt noch */ }
  const names = files.filter(f => /\.md$/.test(f) && f !== 'README.md')

  const wishes = await Promise.all(
    names.map(async f => meta(await fs.readFile(join(dir, f), 'utf8').catch(() => ''), f))
  )

  // priority desc, dann created desc (= neuere zuerst innerhalb gleicher Prio).
  wishes.sort((a, b) => {
    const p = (PRIO_RANK[b.priority] ?? 0) - (PRIO_RANK[a.priority] ?? 0)
    return p !== 0 ? p : b.created.localeCompare(a.created)
  })

  const q = String(getQuery(event).file || '')
  let current = null
  if (q && names.includes(q)) {
    const raw = await fs.readFile(join(dir, q), 'utf8').catch(() => '')
    const { body } = frontmatter(raw)
    current = { ...meta(raw, q), html: render(body) }
  }

  return { wishes, current }
})
