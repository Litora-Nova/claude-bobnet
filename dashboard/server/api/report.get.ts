import { promises as fs } from 'node:fs'
import { resolve, join } from 'node:path'
import { render } from '../utils/md'

// Liest Abschlussberichte (standup/report-*.md) und rendert sie zu HTML.
// Markdown-Renderer in server/utils/md.ts (shared mit feedback/wishes).
//
// Ohne ?file: Liste aller Reports mit Metadaten (Datum/Sprint/Dauer).
// Mit  ?file=report-YYYY-MM-DD.md: zusätzlich der gerenderte Report (current).

const niceDate = (f: string) => f.replace(/^report-/, '').replace(/\.md$/, '')
const clean = (s: string) => s.replace(/\*\*/g, '').replace(/`/g, '').trim()
// Datums-Spalte ist nur 96px breit — `*(deckt 26.05. + 27.05. ab)*` o.ä. raus,
// nur YYYY-MM-DD (oder den ersten Token vor Klammer/Stern) anzeigen.
const trimDate = (s: string) => {
  const iso = s.match(/^\s*(\d{4}-\d{2}-\d{2})\b/)
  if (iso) return iso[1]
  return s.split(/[(*]/)[0].trim() || s
}

// Metadaten aus der Kopf-Tabelle (| **Sprint** | … | bzw. | 🎯 **Sprint** | … |).
// Deutsch + englischer Fallback. Emoji/Whitespace vor dem Label sind ok (28er-
// Reports nutzen 🎯/📅/⏰-Präfixe — vorher fielen Sprint/Datum/Dauer hier durch).
function meta(raw: string, file: string) {
  const row = (...labels: string[]) => {
    for (const l of labels) {
      // `[^|]*?` erlaubt Emoji/Whitespace zwischen dem Spalten-Pipe und **Label**.
      const m = raw.match(new RegExp(`\\|[^|]*?\\*\\*${l}\\*\\*\\s*\\|\\s*(.+?)\\s*\\|`, 'i'))
      if (m) return clean(m[1])
    }
    return ''
  }
  // Fallback-Preview: erste Zeile des "TL;DR — …"-Blockquotes, sonst erster
  // echter Absatz im gesamten Report. Hält die Listen-Vorschau auch ohne TL;DR
  // voll (alte Reports vor 27.05. haben keine TL;DR-Konvention, dann fiel die
  // Vorschau auf '' weil der erste `---`-Block nur die Meta-Tabelle war).
  // Bewusst kurz (~180 Zeichen) für die einzelne Listen-Zeile.
  const tldr = raw.match(/^>\s*\*\*TL;DR\*\*\s*[—-]\s*([^\n]+(?:\n>\s*[^\n]+)*)/m)
  const firstPara = raw.split('\n').find(l => l.trim() && !l.startsWith('#') && !l.startsWith('|') && !l.startsWith('>') && !/^\s*[-=]{3,}\s*$/.test(l))
  const preview = clean((tldr?.[1] || firstPara || '').replace(/\n>\s*/g, ' ').replace(/\s+/g, ' ')).slice(0, 180)
  return {
    file,
    date: trimDate(row('Datum', 'Date') || niceDate(file)),
    sprint: row('Sprint'),
    duration: row('Dauer', 'Duration'),
    preview,
  }
}

export default defineEventHandler(async (event) => {
  const cfg = useRuntimeConfig()
  const dir = resolve(process.cwd(), cfg.standupDir as string)

  let files: string[] = []
  try { files = await fs.readdir(dir) } catch { /* Ordner fehlt noch */ }
  const names = files.filter(f => /^report-.*\.md$/.test(f)).sort().reverse()

  const reports = await Promise.all(
    names.map(async f => meta(await fs.readFile(join(dir, f), 'utf8').catch(() => ''), f))
  )

  const q = String(getQuery(event).file || '')
  let current = null
  if (q && names.includes(q)) {
    const raw = await fs.readFile(join(dir, q), 'utf8').catch(() => '')
    current = { ...meta(raw, q), html: render(raw) }
  }

  return { reports, current }
})
