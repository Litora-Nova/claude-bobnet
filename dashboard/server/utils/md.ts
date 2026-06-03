// Kleiner abhängigkeitsfreier Markdown-Renderer. Genau die Konstrukte, die
// in unseren Reports/Feedback/Wünschen vorkommen: Überschriften, ---, **fett**,
// `code`, Tabellen, Listen, ```fenced code blocks```. Inhalt ist intern/noindex
// und stammt aus eigenen Dateien — Roh-HTML wird trotzdem escaped.
// Extrahiert aus report.get.ts (Stand: 28.05.) für Wiederverwendung.

export const esc = (s: string) =>
  s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')

export function inline(s: string): string {
  return esc(s)
    .replace(/`([^`]+)`/g, '<code>$1</code>')
    .replace(/\*\*([^*]+)\*\*/g, '<strong>$1</strong>')
}

// ── Leichtgewichtiges Syntax-Highlighting (Mini-Eigenbau, 0 Deps) ────────────
// Bewusst KEIN highlight.js o.ä.: das wären >100 KB Bundle für 5 Sprachen, und
// das Dashboard ist absichtlich dependency-arm (eigenes CLAUDE.md-Prinzip).
// Stattdessen ein kleiner, sprach-bewusster Token-Highlighter.
// Läuft komplett serverseitig (SSR-safe, kein Client-JS) und wrappt Tokens in
// <span class="hl-…"> — gefärbt in app.vue/OverlayPanel.vue (GitHub-Dark).
// Ziel: lesbar wie auf GitHub/GitLab, kein perfekter Klon.
//
// SINGLE-PASS-Tokenizer: pro Sprache EINE Regex mit Alternativen in Priorität.
// Die erste passende Alternative gewinnt, danach läuft das Scannen HINTER dem
// Match weiter — so überlappen Tokens nie (Bug-Lehre: mehrere .replace()-Pässe
// matchten in bereits-gewrappte Strings hinein, z. B. `--yes` IN einem '…'-
// String). Gehighlightet wird auf BEREITS escaptem Text (esc() lief vorher),
// d.h. `&lt;` `&amp;` `&gt;` sind im Text — die Alternativen meiden sie.

const KEYWORDS: Record<string, string> = {
  ruby: 'def|end|class|module|do|if|elsif|else|unless|case|when|then|begin|rescue|ensure|while|until|for|in|return|yield|self|nil|true|false|and|or|not|require|require_relative|attr_accessor|attr_reader|attr_writer|raise|new|lambda|proc',
  yaml: 'true|false|null|yes|no|on|off',
  json: 'true|false|null',
  js:   'const|let|var|function|return|if|else|for|while|do|switch|case|break|continue|new|class|extends|import|export|from|default|async|await|try|catch|finally|throw|typeof|instanceof|null|undefined|true|false|this',
  ts:   'const|let|var|function|return|if|else|for|while|do|switch|case|break|continue|new|class|extends|implements|interface|type|import|export|from|default|async|await|try|catch|finally|throw|typeof|instanceof|null|undefined|true|false|this|public|private|readonly',
}

// Eine Tokenizer-Regel: benannte Alternativen → CSS-Klasse. Reihenfolge =
// Priorität. Jede Alternative ist eine eigene Capture-Gruppe; die erste, die
// gefüllt ist, bestimmt die Klasse.
type Rule = { re: RegExp; classes: string[] }

function buildRules(lang: string): Rule | null {
  const l = lang
  if (l === 'bash' || l === 'sh' || l === 'shell' || l === 'console' || l === 'zsh') {
    return {
      classes: ['hl-comment', 'hl-string', 'hl-builtin', 'hl-flag', 'hl-var'],
      re: new RegExp([
        /(#[^\n]*)/,                                                   // Kommentar
        /("[^"\n]*"|'[^'\n]*')/,                                       // String
        /\b(sudo|curl|apt-get|apt|npx|npm|node|ssh|cd|bash|sh|git|cp|mv|rm|ls|cat|echo|chmod|chown|mkdir|kill|xargs|lsof|gitlab-runner)\b/, // Builtin
        /(--?[A-Za-z][\w-]*)/,                                         // Flag
        /(\$\{?\w+\}?)/,                                               // Variable
      ].map(r => r.source).join('|'), 'g'),
    }
  }
  if (l === 'json') {
    return {
      classes: ['hl-key', 'hl-string', 'hl-num', 'hl-keyword'],
      re: new RegExp([
        /("[^"\n]*"(?=\s*:))/,                  // Key (String gefolgt von :)
        /("[^"\n]*")/,                          // String
        /(-?\b\d+(?:\.\d+)?\b)/,                // Zahl
        new RegExp(`\\b(${KEYWORDS.json})\\b`), // Keyword
      ].map(r => r.source).join('|'), 'g'),
    }
  }
  if (l === 'yaml' || l === 'yml') {
    return {
      classes: ['hl-comment', 'hl-key', 'hl-string', 'hl-keyword'],
      re: new RegExp([
        /(#[^\n]*)/,                                  // Kommentar
        /(^[ \t]*[-\s]*[\w.-]+(?=\s*:))/,             // Key am Zeilenanfang
        /("[^"\n]*"|'[^'\n]*')/,                      // String
        new RegExp(`\\b(${KEYWORDS.yaml})\\b`),       // Keyword
      ].map(r => r.source).join('|'), 'gm'),
    }
  }
  if (l === 'ruby' || l === 'rb' || l === 'js' || l === 'javascript' || l === 'ts' || l === 'typescript') {
    const kw = KEYWORDS[l === 'rb' ? 'ruby' : l === 'javascript' ? 'js' : l === 'typescript' ? 'ts' : l] || KEYWORDS.js
    const isRuby = l === 'ruby' || l === 'rb'
    const classes = ['hl-comment', 'hl-string']
    const alts = [
      (isRuby ? /(#[^\n]*)/ : /(\/\/[^\n]*)/).source,
      /("[^"\n]*"|'[^'\n]*'|`[^`\n]*`)/.source,
    ]
    if (isRuby) { classes.push('hl-symbol'); alts.push(/(:[A-Za-z_]\w*)/.source) }
    classes.push('hl-num'); alts.push(/(-?\b\d+(?:\.\d+)?\b)/.source)
    classes.push('hl-keyword'); alts.push(`\\b(${kw})\\b`)
    return { classes, re: new RegExp(alts.join('|'), 'g') }
  }
  return null
}

// Einziger Pass: ersetzt jeden Token-Match durch <span class="…">…</span>.
// Da String.replace global über die kombinierte Regex läuft und immer hinter
// dem letzten Match weitersucht, kann kein Token in einen anderen hineingreifen.
function highlight(code: string, lang: string): string {
  const rule = buildRules(lang)
  if (!rule) return code // unbekannte Sprache → Plain-Code
  return code.replace(rule.re, (m, ...groups) => {
    // groups[0..n-1] = die Alternativen-Captures, dann offset, string.
    const idx = rule.classes.findIndex((_, k) => groups[k] != null)
    if (idx < 0) return m
    return `<span class="${rule.classes[idx]}">${m}</span>`
  })
}

export function render(md: string): string {
  const lines = md.split('\n')
  const out: string[] = []
  let i = 0
  let list: '' | 'ul' | 'ol' = ''
  const closeList = () => { if (list) { out.push(`</${list}>`); list = '' } }

  while (i < lines.length) {
    const line = lines[i]

    // Fenced Code Block: ```lang … ``` (auch eingerückt, z. B. in Listen).
    // Wir merken uns die Einrückung der öffnenden Fence und strippen sie von
    // jeder Inhaltszeile, damit eingerückte Blöcke nicht verschoben rendern.
    const fence = line.match(/^(\s*)```([A-Za-z0-9+#-]*)\s*$/)
    if (fence) {
      closeList()
      const indent = fence[1]
      const lang = fence[2].toLowerCase()
      const buf: string[] = []
      i++
      while (i < lines.length && !/^\s*```\s*$/.test(lines[i])) {
        // Führende Einrückung der Fence entfernen (nur exakt diese), Rest behalten.
        buf.push(lines[i].startsWith(indent) ? lines[i].slice(indent.length) : lines[i])
        i++
      }
      i++ // schließende ``` überspringen (oder EOF)
      const escaped = esc(buf.join('\n'))
      const body = lang ? highlight(escaped, lang) : escaped
      const cls = lang ? ` class="language-${lang}"` : ''
      out.push(`<pre class="codeblock"><code${cls}>${body}</code></pre>`)
      continue
    }

    if (/^\s*\|.*\|\s*$/.test(line) && /^\s*\|[\s:|-]+\|\s*$/.test(lines[i + 1] || '')) {
      closeList()
      const cells = (l: string) => l.trim().replace(/^\||\|$/g, '').split('|').map(c => c.trim())
      const head = cells(line)
      out.push('<table><thead><tr>' + head.map(c => `<th>${inline(c)}</th>`).join('') + '</tr></thead><tbody>')
      i += 2
      while (i < lines.length && /^\s*\|.*\|\s*$/.test(lines[i])) {
        out.push('<tr>' + cells(lines[i]).map(c => `<td>${inline(c)}</td>`).join('') + '</tr>')
        i++
      }
      out.push('</tbody></table>')
      continue
    }

    const h = line.match(/^(#{1,4})\s+(.*)$/)
    if (h) { closeList(); const n = h[1].length; out.push(`<h${n}>${inline(h[2])}</h${n}>`); i++; continue }

    if (/^\s*(-{3,}|\*{3,})\s*$/.test(line)) { closeList(); out.push('<hr/>'); i++; continue }

    const ol = line.match(/^\s*\d+\.\s+(.*)$/)
    if (ol) { if (list !== 'ol') { closeList(); list = 'ol'; out.push('<ol>') } out.push(`<li>${inline(ol[1])}</li>`); i++; continue }

    const ul = line.match(/^\s*[-*]\s+(.*)$/)
    if (ul) { if (list !== 'ul') { closeList(); list = 'ul'; out.push('<ul>') } out.push(`<li>${inline(ul[1])}</li>`); i++; continue }

    if (!line.trim()) { closeList(); i++; continue }

    closeList(); out.push(`<p>${inline(line)}</p>`); i++
  }
  closeList()
  return out.join('\n')
}

// Sehr kleines YAML-Frontmatter-Parsing. Nur Key: Value (Strings/Zahlen/Bool),
// keine Listen/verschachtelten Objekte — reicht für unsere Wishes-Schemata.
// Gibt { data, body } zurück; ohne Frontmatter ist data = {} und body = original.
export function frontmatter(raw: string): { data: Record<string, string>, body: string } {
  const m = raw.match(/^---\n([\s\S]*?)\n---\n?([\s\S]*)$/)
  if (!m) return { data: {}, body: raw }
  const data: Record<string, string> = {}
  for (const line of m[1].split('\n')) {
    const kv = line.match(/^([A-Za-z_][\w-]*)\s*:\s*(.+?)\s*$/)
    if (kv) data[kv[1]] = kv[2].replace(/^["'](.*)["']$/, '$1')
  }
  return { data, body: m[2] }
}
