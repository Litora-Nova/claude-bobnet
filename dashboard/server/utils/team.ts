// Team-Definition (Single Source of Truth fürs Grid) — geladen aus team.config.json.
// Universelle Engine: die KONKRETE Team-Liste lebt NICHT hier, sondern in der
// Projekt-Instanz (team.config.json neben den Heartbeat-Logs). Lokalisiert via
// NUXT_TEAM_CONFIG oder <standupDir>/team.config.json. Fehlt sie → leeres Team
// (Grid zeigt dann nur die vorhandenen <Agent>.log-Files ohne Rollen).
//
// Genutzt von standup.get.ts + bob.get.ts (Grid/Detail, TEAM), heartbeat.post.ts
// (@-Mentions/PO via AGENTS/GROUPS/PO), feedback/wishes/austin-tasks/approvals (roleOf).
import { readdirSync, readFileSync } from 'node:fs'
import { resolve } from 'node:path'

// Display-Kategorie einer Entitaet (Archetyp-Schema `category`). Steuert, WO im
// Dashboard sie erscheint: bob=Team-Grid (Roster) · service=Service-Leiste (eigene
// Session cross-project, z. B. GUPPI/SCUT/Colonel) · coworker=externer Mensch-
// getriebener · helper=ephemer (ROAMER/Sonde, Badge am Eltern-Agent) · human=PO.
export type Category = 'bob' | 'service' | 'coworker' | 'helper' | 'human'

// `id` (z. B. BOB-techlead) ist der STABILE Join-Key zu Archetyp + aktivem Theme —
// `name` ist nur Anzeige (Theme darf umbenennen). Fehlt `id`, faellt das Theme auf
// Namens-Lookup zurueck (rueckwaerts-kompatibel zu id-losen Alt-Configs).
// `category` ueberschreibt (Instanz-Override) die aus dem Archetyp abgeleitete; `parent`
// nennt bei Helfern den Eltern-Agent (Badge-Rendering am Roster-Member).
export type TeamMember = { name: string; id?: string; role: string; order: number; external?: boolean; channel?: string; groups?: string[]; category?: Category; parent?: string }
export type TeamConfig = {
  title?: string
  shortTitle?: string
  demoTitle?: string
  theme?: string            // aktives Theme (Default bobiverse); per NUXT_THEME ueberschreibbar
  po?: { name: string; role?: string; id?: string }
  members: TeamMember[]
  retired?: string[]
}

function locate(): string {
  if (process.env.NUXT_TEAM_CONFIG) return resolve(process.env.NUXT_TEAM_CONFIG)
  const dir = process.env.NUXT_STANDUP_DIR || process.env.STANDUP_DIR || '../standup'
  return resolve(process.cwd(), dir, 'team.config.json')
}

let _cfg: TeamConfig | null = null
function load(): TeamConfig {
  if (_cfg) return _cfg
  try { _cfg = JSON.parse(readFileSync(locate(), 'utf8')) as TeamConfig }
  catch { _cfg = { members: [] } }
  if (!_cfg.members) _cfg.members = []
  return _cfg
}

export const config = (): TeamConfig => load()

// TEAM: Record<name, member> inkl. PO (order 0).
export const TEAM: Record<string, TeamMember> = (() => {
  const c = load()
  const out: Record<string, TeamMember> = {}
  if (c.po) out[c.po.name] = { name: c.po.name, role: c.po.role || '', order: 0 }
  for (const m of c.members) out[m.name] = m
  return out
})()

export const RETIRED = new Set<string>(load().retired || [])
export const PO = load().po?.name || 'Austin'
export const roleOf = (name: string): string => TEAM[name]?.role || ''

// --- Display-Kategorie (category-driven, KEIN Hardcode) --------------------
// Override-Kette: team.config member.category > Archetyp (via id→idPattern) > 'bob'.
// Der Archetyp liefert die Default-Kategorie; die Instanz darf sie pro Member
// ueberschreiben. PO ist immer 'human'. Unbekanntes → 'bob' (Team-Member-Default:
// ein Eintrag im Roster ist konservativer als ihn unsichtbar in einer Service-/
// Helper-Spur verschwinden zu lassen).
const VALID_CATS: ReadonlySet<string> = new Set(['bob', 'service', 'coworker', 'helper', 'human'])

function archetypesDir(): string {
  if (process.env.NUXT_ARCHETYPES_DIR) return resolve(process.env.NUXT_ARCHETYPES_DIR)
  return resolve(process.cwd(), '../archetypes')
}

// id → category, aufgebaut aus allen archetypes/*.json. Zwei Match-Klassen:
//   - exakt:   idPattern ohne Platzhalter (z. B. "BOB-dashboard") → exact-Map
//   - praefix: idPattern mit "<…>"-Platzhalter (z. B. "RMR-<nnn>", "HUMAN-<rolle>")
//              → der Teil vor dem ersten "<" ist das Praefix ("RMR-", "HUMAN-").
// Lookup zuerst exakt, dann laengster passender Praefix.
type ArcheMap = { exact: Record<string, Category>; prefixes: Array<{ prefix: string; category: Category }> }
let _archeMap: ArcheMap | null = null
function archeMap(): ArcheMap {
  if (_archeMap) return _archeMap
  const exact: Record<string, Category> = {}
  const prefixes: Array<{ prefix: string; category: Category }> = []
  try {
    for (const f of readdirSync(archetypesDir())) {
      if (!f.endsWith('.json')) continue
      let a: { idPattern?: string; category?: string }
      try { a = JSON.parse(readFileSync(resolve(archetypesDir(), f), 'utf8')) } catch { continue }
      const cat = a.category
      const pat = a.idPattern
      if (!pat || !cat || !VALID_CATS.has(cat)) continue
      const lt = pat.indexOf('<')
      if (lt === -1) exact[pat] = cat as Category
      else prefixes.push({ prefix: pat.slice(0, lt), category: cat as Category })
    }
  } catch { /* archetypes-Ordner fehlt → leere Map, alles faellt auf 'bob' */ }
  // laengstes Praefix zuerst → spezifischster Treffer gewinnt.
  prefixes.sort((x, y) => y.prefix.length - x.prefix.length)
  _archeMap = { exact, prefixes }
  return _archeMap
}

function categoryFromId(id: string | undefined): Category | null {
  if (!id) return null
  const m = archeMap()
  if (m.exact[id]) return m.exact[id]
  for (const { prefix, category } of m.prefixes) if (id.startsWith(prefix)) return category
  return null
}

export function categoryOf(name: string): Category {
  const c = load()
  if (c.po && name === c.po.name) return (c.po as any).category && VALID_CATS.has((c.po as any).category) ? (c.po as any).category : 'human'
  const member = TEAM[name]
  if (member?.category && VALID_CATS.has(member.category)) return member.category   // Instanz-Override
  return categoryFromId(member?.id) || 'bob'                                        // Archetyp → Default
}

// parent eines Helfers (fuer Badge-Rendering am Eltern-Roster-Member); sonst null.
export const parentOf = (name: string): string | null => TEAM[name]?.parent || null

// @-Mention-Auflösung: AGENTS = interne (nicht-externe) Mitglieder.
export const AGENTS: string[] = load().members.filter(m => !m.external).map(m => m.name)
// GROUPS: 'team' = alle internen; weitere Gruppen aus members[].groups (z. B. 'dev').
export const GROUPS: Record<string, string[]> = (() => {
  const g: Record<string, string[]> = { team: AGENTS.slice() }
  for (const m of load().members) {
    for (const grp of (m.groups || [])) {
      if (grp === 'team') continue
      ;(g[grp] ||= []).push(m.name)
    }
  }
  return g
})()
