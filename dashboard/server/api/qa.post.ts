import { promises as fs } from 'node:fs'
import { join } from 'node:path'
import { tenantOf } from '../utils/tenant'
import { frontmatter } from '../utils/md'

// Q&A schreiben:
//   { action: 'dismiss',   file }   → dismissed: true  + dismissed_at: ISO
//   { action: 'undismiss', file }   → dismissed: false + dismissed_at: ''
//   { action: 'add', question, answer, asked_by?, answered_by? }
//     (Eintrag selten aus dem UI heraus erzeugt — primärer Pfad ist
//      `bash standup/qa-add.sh "…" "…"` von Bob. UI-Add v.a. für Komfort.)

const slug = (s: string) =>
  s.toLowerCase()
    .replace(/[äöüß]/g, c => ({ ä: 'ae', ö: 'oe', ü: 'ue', ß: 'ss' }[c] || c))
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-+|-+$/g, '')
    .slice(0, 50) || 'frage'

const today = () => new Date().toISOString().slice(0, 10)
const stamp = () => new Date().toISOString().slice(0, 16)   // YYYY-MM-DDTHH:MM

function compose(d: Record<string, string>, question: string, answer: string): string {
  return `---
asked_by: ${d.asked_by || 'Austin'}
answered_by: ${d.answered_by || 'Bob'}
created: ${d.created || stamp()}
answered: ${d.answered || stamp()}
dismissed: ${d.dismissed || 'false'}
dismissed_at: ${d.dismissed_at || ''}
---

# Q · ${question}

**Antwort (${d.answered_by || 'Bob'}):**

${answer.trim()}
`
}

// Frage + Antwort aus existierender Datei zurückgewinnen — wir wollen beim
// Dismiss-Toggle nur das Frontmatter aktualisieren, nicht den Inhalt anfassen.
function splitQA(md: string): { question: string; answer: string } {
  const m = md.match(/^#\s+(.+?)\n([\s\S]*)$/m)
  if (!m) return { question: 'Unbenannt', answer: md.trim() }
  return {
    question: m[1].replace(/^Q\s*·\s*/i, '').trim(),
    answer: m[2].replace(/^\s*\*\*Antwort[^\n]*\*\*\s*\n/, '').trim(),
  }
}

export default defineEventHandler(async (event) => {
  const body = await readBody(event)
  const dir = join(tenantOf(event).standupDir, 'qa')
  await fs.mkdir(dir, { recursive: true })

  if (body?.action === 'dismiss' || body?.action === 'undismiss') {
    const file = String(body.file || '')
    if (!/^[\w.-]+\.md$/.test(file)) return { ok: false, error: 'invalid file' }
    const path = join(dir, file)
    const raw = await fs.readFile(path, 'utf8').catch(() => '')
    if (!raw) return { ok: false, error: 'not found' }
    const { data, body: md } = frontmatter(raw)
    // Frontmatter-Patch — Antwort-Body bleibt 1:1.
    const isDismiss = body.action === 'dismiss'
    const next = {
      ...data,
      dismissed: isDismiss ? 'true' : 'false',
      dismissed_at: isDismiss ? stamp() : '',
      // Antwort-Sektion erkennt **Antwort (<wer>)** — wir brauchen den Helper
      // nicht zwingend, behalten aber answered_by konsistent.
      answered_by: data.answered_by || 'Bob',
    }
    const { question, answer } = splitQA(md)
    await fs.writeFile(path, compose(next, question, answer))
    return { ok: true, dismissed: isDismiss }
  }

  if (body?.action === 'add') {
    const question = String(body.question || '').trim().slice(0, 200)
    const answer = String(body.answer || '').trim().slice(0, 8000)
    if (!question) return { ok: false, error: 'question required' }
    const asked_by = String(body.asked_by || 'Austin').trim() || 'Austin'
    const answered_by = String(body.answered_by || 'Bob').trim() || 'Bob'
    const created = today()
    const file = `${created}-${slug(question)}.md`
    let path = join(dir, file), n = 2
    while (await fs.stat(path).then(() => true).catch(() => false)) {
      path = join(dir, file.replace(/\.md$/, `-${n}.md`)); n++
    }
    await fs.writeFile(path, compose(
      { asked_by, answered_by, created: stamp(), answered: stamp(), dismissed: 'false', dismissed_at: '' },
      question, answer,
    ))
    return { ok: true, file: path.split('/').pop() }
  }

  return { ok: false, error: 'unknown action' }
})
