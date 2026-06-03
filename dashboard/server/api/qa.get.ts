import { promises as fs } from 'node:fs'
import { resolve, join } from 'node:path'
import { render, frontmatter } from '../utils/md'

// Liest Q&A-Einträge (standup/qa/YYYY-MM-DD-<slug>.md, Frontmatter
// asked_by/answered_by/created/answered/dismissed/dismissed_at).
//
// Ohne ?file: Liste, sortiert created desc (neueste oben).
// Mit  ?file=<name>.md: zusätzlich `current` mit Frontmatter + gerendertem
// Antwort-HTML + extrahierter Frage.

type QaMeta = {
  file: string
  question: string
  asked_by: string
  answered_by: string
  created: string
  answered: string
  dismissed: boolean
  dismissed_at: string
  html: string         // gerenderte Antwort (Markdown → HTML), Inline-Anzeige
}

// Erste # Überschrift = Frage; "Q · " strippen, sonst Filename ohne .md.
function questionOf(body: string, file: string): string {
  const m = body.match(/^#\s+(.+)$/m)
  return m ? m[1].replace(/^Q\s*·\s*/i, '').trim() : file.replace(/\.md$/, '')
}

// dismissed kommt als String aus dem Frontmatter ('true' / 'false' / leer).
function isDismissed(v: string | undefined): boolean {
  return String(v || '').toLowerCase() === 'true'
}

function meta(raw: string, file: string): QaMeta {
  const { data, body } = frontmatter(raw)
  // Antwort-Body = alles nach der ersten # …-Zeile. Den "**Antwort (Bob):**"-
  // Marker (vom qa-add.sh-Template / compose() im POST) strippen wir hier raus —
  // die UI rendert "Antwort von <wer>:" eh als Header, doppelt wäre redundant.
  const answerMd = body
    .replace(/^#\s+.+\n?/m, '')
    .replace(/^\s*\*\*Antwort[^\n]*\*\*\s*\n+/m, '')
    .trim()
  return {
    file,
    question: questionOf(body, file),
    asked_by: data.asked_by || 'Austin',
    answered_by: data.answered_by || 'Bob',
    created: data.created || file.slice(0, 10),
    answered: data.answered || '',
    dismissed: isDismissed(data.dismissed),
    dismissed_at: data.dismissed_at || '',
    html: render(answerMd),
  }
}

export default defineEventHandler(async (event) => {
  const cfg = useRuntimeConfig()
  const root = resolve(process.cwd(), cfg.standupDir as string)
  const dir = join(root, 'qa')

  let files: string[] = []
  try { files = await fs.readdir(dir) } catch { /* Ordner fehlt noch */ }
  const names = files.filter(f => /\.md$/.test(f) && f !== 'README.md')

  const items = await Promise.all(
    names.map(async f => meta(await fs.readFile(join(dir, f), 'utf8').catch(() => ''), f))
  )

  // created desc (neueste oben). dismissed_at NICHT für Sortierung — bleibt
  // chronologisch nach Frage-Datum, sonst springen Items beim Dismiss.
  items.sort((a, b) => b.created.localeCompare(a.created))

  const q = String(getQuery(event).file || '')
  let current = null
  if (q && names.includes(q)) {
    const raw = await fs.readFile(join(dir, q), 'utf8').catch(() => '')
    const { body } = frontmatter(raw)
    // Antwort = Body ohne die erste # …-Frage-Zeile.
    const answerMd = body.replace(/^#\s+.+\n?/m, '').trim()
    current = { ...meta(raw, q), html: render(answerMd) }
  }

  return { items, current }
})
