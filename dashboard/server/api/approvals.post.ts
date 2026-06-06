import { promises as fs } from 'node:fs'
import { join } from 'node:path'
import { tenantOf } from '../utils/tenant'
import { frontmatter } from '../utils/md'

// Freigaben schreiben:
//   { action: 'add', requested_by, kind, title, body }   // Bob stellt Antrag → pending
//   { action: 'decide', file, decision: 'approved'|'rejected' }  // Austin entscheidet
// Audit via git-blame — keine history-Liste im Frontmatter (wie bei Wünschen).

const slug = (s: string) =>
  s.toLowerCase()
    .replace(/[äöüß]/g, c => ({ ä: 'ae', ö: 'oe', ü: 'ue', ß: 'ss' }[c] || c))
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-+|-+$/g, '')
    .slice(0, 60) || 'freigabe'

// Datum/Zeitstempel in Europe/Berlin (Dashboard-Konvention, Memory
// timezone-europe-berlin is binding — created/decided werden im UI angezeigt).
// sv-SE-Locale liefert ISO-Form 'YYYY-MM-DD' bzw. 'YYYY-MM-DD HH:MM:SS'.
const today = () => new Date().toLocaleDateString('sv-SE', { timeZone: 'Europe/Berlin' })
const stamp = () => new Date().toLocaleString('sv-SE', { timeZone: 'Europe/Berlin', hour12: false }).slice(0, 16)

function compose(d: Record<string, string>, title: string, body: string): string {
  return `---
requested_by: ${d.requested_by || ''}
kind: ${d.kind || 'other'}
status: ${d.status || 'pending'}
created: ${d.created || today()}
decided: ${d.decided || ''}
---

# Freigabe · ${title}

${body.trim()}
`
}

export default defineEventHandler(async (event) => {
  const body = await readBody(event)
  const dir = join(tenantOf(event).standupDir, 'approvals')
  await fs.mkdir(dir, { recursive: true })

  if (body?.action === 'add') {
    const requested_by = String(body.requested_by || '').trim() || 'Anon'
    const kind = (['deploy', 'merge', 'other'].includes(body.kind) ? body.kind : 'other') as string
    const title = String(body.title || '').trim().slice(0, 120) || 'Unbenannt'
    const text = String(body.body || '').trim().slice(0, 5000)
    const created = today()
    const file = `${created}-${slug(title)}.md`
    const path = join(dir, file)
    // Existiert schon? Mit numerischem Suffix deduplizieren.
    let final = path, n = 2
    while (await fs.stat(final).then(() => true).catch(() => false)) {
      final = path.replace(/\.md$/, `-${n}.md`); n++
    }
    await fs.writeFile(final, compose({ requested_by, kind, status: 'pending', created, decided: '' }, title, text))
    return { ok: true, file: final.split('/').pop() }
  }

  if (body?.action === 'decide') {
    const file = String(body.file || '')
    if (!/^[\w.-]+\.md$/.test(file)) return { ok: false, error: 'invalid file' }
    const decision = body.decision === 'approved' ? 'approved' : body.decision === 'rejected' ? 'rejected' : ''
    if (!decision) return { ok: false, error: 'invalid decision' }
    const path = join(dir, file)
    const raw = await fs.readFile(path, 'utf8').catch(() => '')
    if (!raw) return { ok: false, error: 'not found' }
    const { data, body: md } = frontmatter(raw)
    const titleM = md.match(/^#\s+(.+)$/m)
    const title = titleM ? titleM[1].replace(/^(Approval|Freigabe)\s*·\s*/i, '').trim() : 'Unbenannt'
    const rest = md.replace(/^#\s+.+\n?/m, '').trim()
    await fs.writeFile(path, compose({ ...data, status: decision, decided: stamp() }, title, rest))
    return { ok: true, status: decision }
  }

  return { ok: false, error: 'unknown action' }
})
