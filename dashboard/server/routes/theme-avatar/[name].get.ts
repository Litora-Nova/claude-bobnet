import { promises as fs } from 'node:fs'
import { join } from 'node:path'
import { avatarFileOf, avatarsDirOf, defaultAvatar } from '../../utils/theme'

// Theme-aware Avatar-Auslieferung: /theme-avatar/<Roster-Name> → PNG aus dem
// aktiven Theme. HARTE Regel (Austin): Team-Mitglieder werden NIE per Emoji
// gezeigt — fehlt ein Persona-Avatar, kommt das Theme-Default-Bild (Anonymous-/
// Hacker-Maske). Zweistufig: persona.avatar → defaultAvatar → (nur wenn beides
// fehlt) 404, dann faellt der Client auf das statische /avatars/default.png.
export default defineEventHandler(async (event) => {
  const name = String(getRouterParam(event, 'name') || '').replace(/[^A-Za-z0-9 _.-]/g, '')
  const dir = avatarsDirOf()
  setHeader(event, 'Content-Type', 'image/png')
  setHeader(event, 'Cache-Control', 'public, max-age=300')
  try {
    return await fs.readFile(join(dir, avatarFileOf(name)))
  } catch {
    try {
      return await fs.readFile(join(dir, defaultAvatar()))
    } catch {
      setResponseStatus(event, 404)
      return ''
    }
  }
})
