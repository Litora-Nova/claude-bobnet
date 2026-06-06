// Team-Definition (Single Source of Truth fürs Grid) — geladen aus team.config.json.
// Universelle Engine: die KONKRETE Team-Liste lebt NICHT hier, sondern in der
// Projekt-Instanz (team.config.json neben den Heartbeat-Logs).
//
// Multi-tenant (#9): KEINE Modul-Globals mehr — der Team-Kontext wird pro Tenant
// aufgelöst (`teamOf(tenant)`) und mtime-gecacht (Config-Änderung ohne Neustart
// sichtbar, kein Read pro Request). Die Archetyp-Map (Engine-Ebene, tenant- und
// theme-unabhängig) bleibt global. Fehlende Config → leeres Team (Grid zeigt dann
// nur die vorhandenen <Agent>.log-Files ohne Rollen).
import { readdirSync, readFileSync, statSync } from 'node:fs'
import { resolve } from 'node:path'
import type { Tenant } from './tenant'

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
  theme?: string            // aktives Theme; Vorrang-Kette siehe theme.ts
  po?: { name: string; role?: string; id?: string }
  members: TeamMember[]
  retired?: string[]
}

// Der komplette Team-Kontext EINES Tenants — alles, was vorher Modul-Global war.
export type TeamCtx = {
  config: TeamConfig
  TEAM: Record<string, TeamMember>
  RETIRED: Set<string>
  PO: string
  AGENTS: string[]
  GROUPS: Record<string, string[]>
  roleOf: (name: string) => string
  categoryOf: (name: string) => Category
  parentOf: (name: string) => string | null
}

// --- Archetyp-Map (global, Engine-Ebene) ------------------------------------
// id → category, aufgebaut aus allen archetypes/*.json. Zwei Match-Klassen:
//   - exakt:   idPattern ohne Platzhalter (z. B. "BOB-dashboard") → exact-Map
//   - praefix: idPattern mit "<…>"-Platzhalter (z. B. "RMR-<nnn>", "HUMAN-<rolle>")
//              → der Teil vor dem ersten "<" ist das Praefix ("RMR-", "HUMAN-").
// Lookup zuerst exakt, dann laengster passender Praefix.
const VALID_CATS: ReadonlySet<string> = new Set(['bob', 'service', 'coworker', 'helper', 'human'])

function archetypesDir(): string {
  if (process.env.NUXT_ARCHETYPES_DIR) return resolve(process.env.NUXT_ARCHETYPES_DIR)
  return resolve(process.cwd(), '../archetypes')
}

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

// --- per-Tenant Team-Kontext (mtime-gecacht) ---------------------------------
function buildCtx(config: TeamConfig): TeamCtx {
  const TEAM: Record<string, TeamMember> = {}
  if (config.po) TEAM[config.po.name] = { name: config.po.name, role: config.po.role || '', order: 0 }
  for (const m of config.members) TEAM[m.name] = m

  const AGENTS = config.members.filter(m => !m.external).map(m => m.name)
  const GROUPS: Record<string, string[]> = { team: AGENTS.slice() }
  for (const m of config.members) {
    for (const grp of (m.groups || [])) {
      if (grp === 'team') continue
      ;(GROUPS[grp] ||= []).push(m.name)
    }
  }

  // Override-Kette: team.config member.category > Archetyp (via id→idPattern) > 'bob'.
  // PO ist immer 'human'. Unbekanntes → 'bob' (Roster ist konservativer als unsichtbar).
  const categoryOf = (name: string): Category => {
    if (config.po && name === config.po.name) {
      const poCat = (config.po as any).category
      return poCat && VALID_CATS.has(poCat) ? poCat : 'human'
    }
    const member = TEAM[name]
    if (member?.category && VALID_CATS.has(member.category)) return member.category   // Instanz-Override
    return categoryFromId(member?.id) || 'bob'                                        // Archetyp → Default
  }

  return {
    config,
    TEAM,
    RETIRED: new Set<string>(config.retired || []),
    PO: config.po?.name || 'Austin',
    AGENTS,
    GROUPS,
    roleOf: (name) => TEAM[name]?.role || '',
    categoryOf,
    parentOf: (name) => TEAM[name]?.parent || null,
  }
}

const _ctxCache = new Map<string, { mtimeMs: number; ctx: TeamCtx }>()

export function teamOf(tenant: Tenant): TeamCtx {
  const path = tenant.teamConfigPath
  let mtimeMs = 0
  try { mtimeMs = statSync(path).mtimeMs } catch { /* fehlt → leeres Team (mtime 0) */ }
  const hit = _ctxCache.get(path)
  if (hit && hit.mtimeMs === mtimeMs) return hit.ctx
  let config: TeamConfig
  try { config = JSON.parse(readFileSync(path, 'utf8')) as TeamConfig } catch { config = { members: [] } }
  if (!config.members) config.members = []
  const ctx = buildCtx(config)
  _ctxCache.set(path, { mtimeMs, ctx })
  return ctx
}
