import { promises as fs } from 'node:fs'
import { resolve, join } from 'node:path'
import { render } from '../utils/md'
import { roleOf } from '../utils/team'

// Liest ALLE Markdown-Files in standup/feedback/ und rendert sie zu HTML.
//
// Zwei Klassen (gleicher Tab — Austin's Wunsch: „ALLES Feedback sichtbar"):
//   • Sprint-Runden:   YYYY-MM-DD.md, YYYY-MM-DD-am.md, YYYY-MM-DD-eve.md
//     → mit `## @Name`-Sektionen + (a)/(b)/(c)-Antworten → Aggregation byQuestion.
//   • Sonstige Reports: YYYY-MM-DD-<author-or-tag>-<rest>.md (Quality-Checks,
//     Live-Bug-Reports, Coverage-Audits etc.) → kein festes Schema, nur Markdown
//     rendern. Author + Type aus Filename ableiten, damit Filter/Badge geht.
//
// Ohne ?file: Liste aller Einträge (neueste zuerst).
// Mit  ?file=...: zusätzlich `current` mit gerendertem HTML.

// Sprint-Runden-Pattern: optional `-am` / `-eve` / nichts.
const SPRINT_RE = /^(\d{4}-\d{2}-\d{2})(?:-(am|eve|pm|morgen|abend|mid))?\.md$/i
// Generisch: jedes YYYY-MM-DD-<rest>.md (Quality-Checks, Audits, Live-Bugs).
const DATED_RE = /^(\d{4}-\d{2}-\d{2})-(.+)\.md$/

// Vor dem Render Agent-Sektionen mit Rolle annotieren:
//   `## @Bill ✅`  →  `## @Bill · Backend + Infra ✅`
function annotateAgents(md: string): string {
  return md.replace(/^(##\s+@(\w+))([ \t]+(?:✅|⏳[^\n]*))?$/gm, (m, head, name, suffix = '') => {
    const role = roleOf(name)
    return role ? `${head} · ${role}${suffix}` : m
  })
}

// Erste **Sprint-Endstand:**-Zeile als Untertitel (Sprint-Runden).
function sprintPreview(raw: string): string {
  const m = raw.match(/\*\*Sprint-Endstand:\*\*\s*(.+)/)
  return m ? m[1].trim() : ''
}

// Wie viele Agent-Sektionen (`## @Name`)?
function agentCount(raw: string): number {
  const m = raw.match(/^##\s+@\w+/gm)
  return m ? m.length : 0
}

// Fallback-Preview für sonstige Reports: H1 ohne Datum, sonst erste echte
// Textzeile. Knapp gehalten für die Listen-Zeile.
function genericPreview(raw: string): string {
  const h1 = raw.match(/^#\s+(.+)$/m)
  if (h1) return h1[1].replace(/\d{4}-\d{2}-\d{2}.*$/, '').replace(/[—\-·]+\s*$/, '').trim().slice(0, 140)
  const first = raw.split('\n').find(l => l.trim() && !l.startsWith('#') && !l.startsWith('>') && !l.startsWith('|'))
  return (first || '').trim().slice(0, 140)
}

// Aus Filename Author + Type erraten.
// Beispiele:
//   2026-05-29-bill-quality-check.md    → author=Bill, type=quality-check
//   2026-05-29-austin-live-bugs.md      → author=Austin, type=live-bugs
//   2026-05-29-coverage-audit.md        → author='',     type=coverage-audit
//   2026-05-29-am.md                    → author='',     type=round (Sprint-Runde)
const KNOWN_AUTHORS = new Set([
  'Austin', 'Bob', 'Bill', 'Howard', 'Dexter', 'Loki', 'Riker', 'Marvin',
  'Garfield', 'Bender', 'Homer', 'Mario', 'Tim', 'Henry', 'Hugh',
])
function metaFromFilename(file: string): { date: string; author: string; type: string; kind: 'round' | 'other' } {
  const sprint = SPRINT_RE.exec(file)
  if (sprint) return { date: sprint[1], author: '', type: sprint[2] ? `round-${sprint[2].toLowerCase()}` : 'round', kind: 'round' }
  const dated = DATED_RE.exec(file)
  if (dated) {
    const [, date, rest] = dated
    const parts = rest.split('-')
    const first = parts[0]
    const cap = first.charAt(0).toUpperCase() + first.slice(1).toLowerCase()
    if (KNOWN_AUTHORS.has(cap)) {
      return { date, author: cap, type: parts.slice(1).join('-') || 'note', kind: 'other' }
    }
    return { date, author: '', type: rest, kind: 'other' }
  }
  return { date: '', author: '', type: 'misc', kind: 'other' }
}

function meta(raw: string, file: string) {
  const fm = metaFromFilename(file)
  if (fm.kind === 'round') {
    return { file, date: fm.date, author: fm.author, type: fm.type, kind: 'round' as const, preview: sprintPreview(raw), agents: agentCount(raw) }
  }
  return { file, date: fm.date, author: fm.author, type: fm.type, kind: 'other' as const, preview: genericPreview(raw), agents: 0 }
}

// Aggregation pro Frage: parst `## @Name`-Sektionen → (a)/(b)/(c).
// Nur sinnvoll für Sprint-Runden — sonstige Reports liefern leeres Objekt zurück.
// Antworten werden serverseitig zu HTML gerendert (volles Markdown: Listen,
// Tabellen, Code-Blöcke) statt nur Inline-Mini-Render im Client. Austin-Wunsch:
// „Markdown→HTML im Feedback" — Listen/Aufzählungen kamen vorher als roher
// Text raus, weil der inline()-Renderer im Client nur **bold**/`code`/<br> kann.
function byQuestion(raw: string): Record<string, Array<{ agent: string; role: string; answer: string; html: string }>> {
  const out: Record<string, Array<{ agent: string; role: string; answer: string; html: string }>> = { '(a)': [], '(b)': [], '(c)': [] }
  const parts = raw.split(/^##\s+@(\w+)[^\n]*\n/gm)
  for (let i = 1; i < parts.length; i += 2) {
    const agent = parts[i]
    let body = parts[i + 1] || ''
    body = body.split(/^#\s+/m)[0]
    const found: Record<string, string> = {}
    const re = /\*\*\(([abc])\)\*\*\s*([\s\S]*?)(?=\n\*\*\(([abc])\)\*\*|\n##\s|\n---|\n#\s|$)/g
    let m: RegExpExecArray | null
    while ((m = re.exec(body))) found[`(${m[1]})`] = m[2].trim()
    for (const q of ['(a)', '(b)', '(c)']) {
      if (found[q]) out[q].push({ agent, role: roleOf(agent), answer: found[q], html: render(found[q]) })
    }
  }
  return out
}

export default defineEventHandler(async (event) => {
  const cfg = useRuntimeConfig()
  const root = resolve(process.cwd(), cfg.standupDir as string)
  const dir = join(root, 'feedback')

  let files: string[] = []
  try { files = await fs.readdir(dir) } catch { /* Ordner fehlt noch */ }
  // Alle *.md außer README.md — kein Format-Filter mehr.
  const names = files.filter(f => f.endsWith('.md') && f.toLowerCase() !== 'readme.md')
  // Sortierung: Datum desc, dann Filename desc (Sprint-Runde vor Sub-Reports
  // am selben Tag, weil ohne Suffix kommt sie nach Sortierung zuerst).
  names.sort((a, b) => b.localeCompare(a))

  const rounds = await Promise.all(
    names.map(async f => meta(await fs.readFile(join(dir, f), 'utf8').catch(() => ''), f))
  )

  const q = String(getQuery(event).file || '')
  let current = null
  if (q && names.includes(q)) {
    const raw = await fs.readFile(join(dir, q), 'utf8').catch(() => '')
    const m = meta(raw, q)
    current = { ...m, html: render(annotateAgents(raw)), byQuestion: m.kind === 'round' ? byQuestion(raw) : {} }
  }

  return { rounds, current }
})
