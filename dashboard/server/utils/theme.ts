// Theme-Layer (Schicht ②): gibt demselben Maschinenkern Namen/Avatar/Bio.
// Gekeyt ueber die stabile Archetyp-`id` (team.config member.id) — `name` ist nur
// Anzeige. Aktives Theme: NUXT_THEME > team.config.theme > "bobiverse".
// Themes liegen in <themesDir> (Default ../themes relativ zum App-Root, per
// NUXT_THEMES_DIR ueberschreibbar).
//
// HARTE REGEL (Austin): Team-Mitglieder werden im BobNet AUSSCHLIESSLICH als Bild
// angezeigt — NIE als Emoji, auch nicht als Fallback/Option. Fehlt ein Avatar →
// defaultAvatar (Anonymous-/Hacker-Maske). KEIN emoji-Feld mehr.
import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { TEAM, config } from './team'

type I18n = string | Record<string, string>
type Persona = { name: string; avatar?: string; bio?: I18n; positionLabel?: I18n }
type Theme = {
  id: string
  label?: I18n
  description?: I18n
  leadTitle?: I18n
  defaultAvatar?: string
  settings?: Record<string, any>
  strings?: Record<string, I18n>
  personas: Record<string, Persona>
}

const DEFAULT_LOCALE = (process.env.NUXT_THEME_LOCALE || 'de').toLowerCase()

// Lokalisierten Wert aufloesen: Plain-String passthrough, sonst locale → de → en → erster.
export function i18n(v: I18n | undefined, locale: string = DEFAULT_LOCALE): string {
  if (v == null) return ''
  if (typeof v === 'string') return v
  return v[locale] ?? v.de ?? v.en ?? Object.values(v)[0] ?? ''
}

function themesDir(): string {
  if (process.env.NUXT_THEMES_DIR) return resolve(process.env.NUXT_THEMES_DIR)
  return resolve(process.cwd(), '../themes')
}

function activeThemeId(): string {
  return process.env.NUXT_THEME || config().theme || 'bobiverse'
}

let _theme: Theme | null = null
let _loadedId: string | null = null
function load(): Theme {
  const id = activeThemeId()
  if (_theme && _loadedId === id) return _theme
  try {
    _theme = JSON.parse(readFileSync(resolve(themesDir(), id, 'theme.json'), 'utf8')) as Theme
  } catch {
    _theme = { id, personas: {} }   // Theme fehlt → leer, Engine laeuft mit Namens-/Emoji-Fallback weiter
  }
  if (!_theme.personas) _theme.personas = {}
  _loadedId = id
  return _theme
}

// Name → Persona (fuer schnellen Fallback ohne id).
function byName(): Record<string, Persona> {
  const t = load(), out: Record<string, Persona> = {}
  for (const p of Object.values(t.personas)) if (p?.name) out[p.name] = p
  return out
}

// Persona zu einem Roster-Namen aufloesen: erst member.id → personas[id],
// sonst Persona mit gleichem Anzeigenamen (id-lose Alt-Configs).
export function personaOf(agentName: string): Persona | null {
  const t = load()
  const member = TEAM[agentName]
  if (member?.id && t.personas[member.id]) return t.personas[member.id]
  return byName()[agentName] || null
}

export const defaultAvatar = (): string => load().defaultAvatar || 'default.png'
export const activeTheme = (): string => activeThemeId()
// Theme-Settings (erweiterbar). showAvatars default true; false = nur Name (nie Emoji).
export const themeSettings = (): Record<string, any> => {
  const s = load().settings || {}
  return { showAvatars: s.showAvatars !== false, ...s }
}
export const themeMeta = () => {
  const t = load()
  return {
    id: t.id,
    label: i18n(t.label) || t.id,
    leadTitle: i18n(t.leadTitle),
    defaultAvatar: defaultAvatar(),
    settings: themeSettings(),
    strings: t.strings || {},
  }
}

// Anzeige-Helfer (alle keyed auf den stabilen Roster-Namen):
export const displayNameOf = (name: string): string => personaOf(name)?.name || name
export const bioOf = (name: string, locale: string = DEFAULT_LOCALE): string => i18n(personaOf(name)?.bio, locale)
// Avatar-Dateiname im aktiven Theme — Persona-Avatar ODER defaultAvatar (Bild).
// Liefert IMMER einen Dateinamen (nie null) → BobNet zeigt nie ein Emoji.
export const avatarFileOf = (name: string): string => personaOf(name)?.avatar || defaultAvatar()
export const avatarsDirOf = (): string => resolve(themesDir(), activeThemeId(), 'avatars')
