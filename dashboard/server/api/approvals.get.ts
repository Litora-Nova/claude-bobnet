import { promises as fs } from 'node:fs'
import { join } from 'node:path'
import { render, frontmatter } from '../utils/md'
import { tenantOf } from '../utils/tenant'
import { teamOf } from '../utils/team'

// Liest Freigabe-Anträge (standup/approvals/YYYY-MM-DD-<slug>.md, Frontmatter
// requested_by/kind/status/created/decided — siehe standup/approvals/README.md).
// Bobs tragen Requests ein, der PO entscheidet (approve/reject) via approvals.post.
//
// Ohne ?file: Liste (pending zuerst, dann created desc).
// Mit  ?file=<name>.md: zusätzlich `current` mit Frontmatter + gerendertem Body-HTML.

type ApprovalMeta = {
  file: string
  title: string
  requested_by: string
  requestedByRole: string
  kind: string
  status: 'pending' | 'approved' | 'rejected' | string
  created: string
  decided: string
}

// pending oben (Rang 2), entschiedene darunter (Rang 1) — innerhalb created desc.
const STATUS_RANK: Record<string, number> = { pending: 2, approved: 1, rejected: 1 }

function titleOf(body: string, file: string): string {
  const m = body.match(/^#\s+(.+)$/m)
  return m ? m[1].replace(/^(Approval|Freigabe)\s*·\s*/i, '').trim() : file.replace(/\.md$/, '')
}

function meta(raw: string, file: string, roleOf: (n: string) => string): ApprovalMeta {
  const { data, body } = frontmatter(raw)
  const requested_by = data.requested_by || ''
  return {
    file,
    title: titleOf(body, file),
    requested_by,
    requestedByRole: roleOf(requested_by),
    kind: data.kind || 'other',
    status: (data.status || 'pending') as ApprovalMeta['status'],
    created: data.created || file.slice(0, 10),
    decided: data.decided || '',
  }
}

export default defineEventHandler(async (event) => {
  const tenant = tenantOf(event)
  const team = teamOf(tenant)
  const dir = join(tenant.standupDir, 'approvals')

  let files: string[] = []
  try { files = await fs.readdir(dir) } catch { /* Ordner fehlt noch */ }
  const names = files.filter(f => /\.md$/.test(f) && f !== 'README.md')

  const approvals = await Promise.all(
    names.map(async f => meta(await fs.readFile(join(dir, f), 'utf8').catch(() => ''), f, team.roleOf))
  )

  approvals.sort((a, b) => {
    const s = (STATUS_RANK[b.status] ?? 0) - (STATUS_RANK[a.status] ?? 0)
    return s !== 0 ? s : b.created.localeCompare(a.created)
  })

  const q = String(getQuery(event).file || '')
  let current = null
  if (q && names.includes(q)) {
    const raw = await fs.readFile(join(dir, q), 'utf8').catch(() => '')
    const { body } = frontmatter(raw)
    current = { ...meta(raw, q, team.roleOf), html: render(body) }
  }

  return { approvals, current }
})
