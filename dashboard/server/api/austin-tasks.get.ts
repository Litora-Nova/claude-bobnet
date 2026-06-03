import { promises as fs } from 'node:fs'
import { resolve, join } from 'node:path'
import { render } from '../utils/md'
import { roleOf } from '../utils/team'

// Liest Austins „Tasks mit Details" aus standup/austin.tasks.md.
//
// Format: ## <Titel> + Body bis zur nächsten ##-Sektion (oder bis zum
// `---\n### ARCHIV:`-Trenner — alles darunter zählt als Archiv).
//   ## Wording-Entscheidung: ... (Loki, 2026-05-29)
//
//   <Markdown-Body mit allen Details — Listen, Alternativen, Diskussion>
//
//   ## Nächste Task ...
//
// Done-State (Austin 2026-05-30 02:35: "Sollte verschwinden wenn erledigt"):
//   • Titel beginnt mit `~~…~~` (Strikethrough)                      → done
//   • Titel enthält ✅ ODER "ENTSCHIEDEN" ODER "ARCHIV" ODER "DONE"   → done
//     (Markdown-friendly Pflege: Austin/Bobs schreiben einfach ✅ rein)
//   • Body enthält explizit `- [x] erledigt` als erste Checkbox        → done
//   • Unter `### ARCHIV:`-Sektion (separater Bereich, alles archived)  → done
//
// Author wird aus dem Titel-Suffix `(Name, …)` geraten — heuristisch, fällt
// auf '' zurück wenn nichts passt. Rolle kommt aus roleOf().
//
// Rückgabe: { tasks: [{ id, title, author, authorRole, done, html, raw }] }
// HTML ist serverseitig vorgerendert (analog Feedback/Q&A), damit der Client
// kein Markdown-Lib braucht.

const AUTHOR_RE = /\(([A-Z][a-zA-Z]+)(?:[,\s][^)]*)?\)/

// Strikethrough-Titel (~~…~~) ODER explizites "- [x]" als erste Checkbox.
const STRIKE_RE = /^~~.*~~$/
const DONE_CHECKBOX_RE = /^\s*-\s*\[x\]\s+/im
// Done-Marker im Titel: ✅-Emoji oder eines der Keywords (case-insensitive,
// ganzes Wort). „ARCHIV" matcht NICHT „Archive-View" o.ä. — wir wollen den
// expliziten Done-Marker. Spezielles Pattern fuer alle 3 Texte + Emoji.
const DONE_TITLE_RE = /(?:✅|\bENTSCHIEDEN\b|\bARCHIV\b|\bDONE\b)/i

// Trenner: `---` gefolgt von `### ARCHIV:` markiert den Archiv-Block.
// Tasks darunter sind alle done (Austin's manuelles „weg in den Schrank").
const ARCHIV_RE = /^---\s*\n+###\s+ARCHIV:/m

function parseTasks(raw: string): Array<{
  id: number; title: string; author: string; authorRole: string;
  done: boolean; archived: boolean; html: string; body: string
}> {
  // Erst Archiv-Bereich abtrennen — alles darunter ist archived/done.
  const archMatch = raw.match(ARCHIV_RE)
  const liveRaw = archMatch ? raw.slice(0, archMatch.index) : raw
  const archRaw = archMatch ? raw.slice(archMatch.index!) : ''

  const collect = (block: string, archived: boolean) => {
    // Split an `## `-Headern (auf Zeilenanfang). Top-Level `# `-Header
    // (Datei-Titel) und tiefer geschachtelte `### ` ignorieren wir hier
    // bewusst — Tasks sind immer auf H2.
    const parts = block.split(/^##\s+(.+)$/m)
    // parts = [pre, title1, body1, title2, body2, …]
    const out: ReturnType<typeof parseTasks> = []
    for (let i = 1; i < parts.length; i += 2) {
      const titleRaw = (parts[i] || '').trim()
      const body = (parts[i + 1] || '').trim()
      if (!titleRaw) continue
      // Strikethrough = done. Wir zeigen den Titel ohne ~~ in der UI an.
      const isStrike = STRIKE_RE.test(titleRaw)
      const title = isStrike ? titleRaw.replace(/^~~|~~$/g, '').trim() : titleRaw
      const done = archived || isStrike || DONE_TITLE_RE.test(title) || DONE_CHECKBOX_RE.test(body)
      const am = title.match(AUTHOR_RE)
      const author = am ? am[1] : ''
      out.push({
        id: 0,                                   // wird unten gesetzt
        title, author, authorRole: roleOf(author),
        done, archived,
        html: render(body), body,
      })
    }
    return out
  }

  const tasks = [...collect(liveRaw, false), ...collect(archRaw, true)]
  return tasks.map((t, i) => ({ ...t, id: i }))
}

export default defineEventHandler(async () => {
  const cfg = useRuntimeConfig()
  const dir = resolve(process.cwd(), cfg.standupDir as string)
  const raw = await fs.readFile(join(dir, 'austin.tasks.md'), 'utf8').catch(() => '')
  const tasks = parseTasks(raw)
  return { tasks }
})
