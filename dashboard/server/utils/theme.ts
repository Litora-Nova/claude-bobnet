// Theme-Layer (Schicht ②): gibt demselben Maschinenkern Namen/Avatar/Bio.
// Gekeyt ueber die stabile Archetyp-`id` (team.config member.id) — `name` ist nur
// Anzeige. Themes liegen in <themesDir> (Default ../themes relativ zum App-Root,
// per NUXT_THEMES_DIR ueberschreibbar — EIN Themes-Verzeichnis fuer alle Tenants).
//
// Multi-tenant (#9): Theme-Kontext pro Tenant via `themeOf(tenant, team)`.
// Aktives Theme — Vorrang-Kette:
//   Modus A (?project=):  Registry-theme > team.config.theme > "bobiverse"
//                         (env NUXT_THEME gilt hier NICHT — sie wuerde im Hub
//                          jedem Tenant dasselbe Theme aufzwingen)
//   Modus B (Env):        NUXT_THEME > team.config.theme > "bobiverse"  (wie bisher)
//
// HARTE REGEL (PO): Team-Mitglieder werden im BobNet AUSSCHLIESSLICH als Bild
// angezeigt — NIE als Emoji, auch nicht als Fallback/Option. Fehlt ein Avatar →
// defaultAvatar (Anonymous-/Hacker-Maske). KEIN emoji-Feld.
import { readFileSync, statSync } from 'node:fs'
import { resolve } from 'node:path'
import type { Tenant } from './tenant'
import type { TeamCtx } from './team'

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

export function themeIdOf(tenant: Tenant, team: TeamCtx): string {
  if (tenant.uid) return tenant.themeId || team.config.theme || 'bobiverse'
  return process.env.NUXT_THEME || team.config.theme || 'bobiverse'
}

// --- Theme-Datei (mtime-gecacht pro Theme-Id) --------------------------------
const _themeCache = new Map<string, { mtimeMs: number; theme: Theme }>()
function loadTheme(id: string): Theme {
  const path = resolve(themesDir(), id, 'theme.json')
  let mtimeMs = 0
  try { mtimeMs = statSync(path).mtimeMs } catch { /* fehlt → leeres Theme */ }
  const hit = _themeCache.get(id)
  if (hit && hit.mtimeMs === mtimeMs) return hit.theme
  let theme: Theme
  try { theme = JSON.parse(readFileSync(path, 'utf8')) as Theme }
  catch { theme = { id, personas: {} } }   // Theme fehlt → leer, Engine laeuft mit Namens-Fallback weiter
  if (!theme.personas) theme.personas = {}
  _themeCache.set(id, { mtimeMs, theme })
  return theme
}

// Der komplette Theme-Kontext EINES Tenants (Anzeige-Helfer, keyed auf Roster-Namen).
export type ThemeCtx = {
  id: string
  personaOf: (agentName: string) => Persona | null
  displayNameOf: (name: string) => string
  bioOf: (name: string, locale?: string) => string
  avatarFileOf: (name: string) => string
  avatarsDir: string
  defaultAvatar: string
  settings: Record<string, any>
  meta: { id: string; label: string; leadTitle: string; defaultAvatar: string; settings: Record<string, any>; strings: Record<string, I18n> }
}

export function themeOf(tenant: Tenant, team: TeamCtx): ThemeCtx {
  const id = themeIdOf(tenant, team)
  const t = loadTheme(id)

  // Name → Persona (Fallback fuer id-lose Alt-Configs).
  const byName: Record<string, Persona> = {}
  for (const p of Object.values(t.personas)) if (p?.name) byName[p.name] = p

  const personaOf = (agentName: string): Persona | null => {
    // agentName kann der Log-/Routing-Key (uid, z. B. `bobnet-infra`) ODER der Anzeige-Name
    // sein. Member per uid ODER name auflösen, dann über den ANZEIGE-Namen die Persona finden
    // (Name → Gesicht; heisst ein Member wie eine Theme-Persona, kriegt er deren Avatar/Bio).
    // Klare Rollenteilung: `id` = struktureller Join (Archetyp/Kategorie, s. team.ts), `name`
    // = Identitaet. Kein Namens-Treffer → id-Persona (Theme-Default), sonst reiner Fallback.
    const member = team.memberOf ? team.memberOf(agentName) : team.TEAM[agentName]
    const display = member?.name || agentName
    if (byName[display]) return byName[display]
    if (member?.id && t.personas[member.id]) return t.personas[member.id]
    return byName[agentName] || null
  }

  const defaultAvatar = t.defaultAvatar || 'default.png'
  // Theme-Settings (erweiterbar). showAvatars default true; false = nur Name (nie Emoji).
  const settings = { showAvatars: (t.settings || {}).showAvatars !== false, ...(t.settings || {}) }

  return {
    id,
    personaOf,
    // Anzeige = Member-Name (per uid ODER name aufgelöst; Contract: members[].name = Anzeige
    // fuer Commit + Dashboard, git-identity nimmt ihn schon), sonst Persona-Name, sonst Key.
    displayNameOf: (name) => (team.memberOf ? team.memberOf(name) : team.TEAM[name])?.name || personaOf(name)?.name || name,
    bioOf: (name, locale = DEFAULT_LOCALE) => i18n(personaOf(name)?.bio, locale),
    // Liefert IMMER einen Dateinamen (nie null) → BobNet zeigt nie ein Emoji.
    avatarFileOf: (name) => personaOf(name)?.avatar || defaultAvatar,
    avatarsDir: resolve(themesDir(), id, 'avatars'),
    defaultAvatar,
    settings,
    meta: {
      id: t.id,
      label: i18n(t.label) || t.id,
      leadTitle: i18n(t.leadTitle),
      defaultAvatar,
      settings,
      strings: t.strings || {},
    },
  }
}
