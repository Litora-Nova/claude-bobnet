import { promises as fs } from 'node:fs'
import { extname, join } from 'node:path'
import { tenantOf } from '../../utils/tenant'
import { teamOf } from '../../utils/team'
import { themeOf } from '../../utils/theme'

// Theme-aware Avatar-Auslieferung: /theme-avatar/<Roster-Name> → Bild aus dem
// aktiven Theme. HARTE Regel (PO): Team-Mitglieder werden NIE per Emoji
// gezeigt — fehlt ein Persona-Avatar, kommt das Theme-Default-Bild (Anonymous-/
// Hacker-Maske). Zweistufig: persona.avatar → defaultAvatar → (nur wenn beides
// fehlt) 404, dann faellt der Client auf das statische /avatars/default.png.
export default defineEventHandler(async (event) => {
  const name = String(getRouterParam(event, 'name') || '').replace(/[^A-Za-z0-9 _.-]/g, '')
  const tenant = tenantOf(event)
  const theme = themeOf(tenant, teamOf(tenant))
  const dir = theme.avatarsDir
  setHeader(event, 'Cache-Control', 'public, max-age=300')
  try {
    const file = theme.avatarFileOf(name)
    setHeader(event, 'Content-Type', contentTypeOf(file))
    return await fs.readFile(join(dir, file))
  } catch {
    try {
      setHeader(event, 'Content-Type', contentTypeOf(theme.defaultAvatar))
      return await fs.readFile(join(dir, theme.defaultAvatar))
    } catch {
      setResponseStatus(event, 404)
      return ''
    }
  }
})

function contentTypeOf(file: string): string {
  switch (extname(file).toLowerCase()) {
    case '.webp': return 'image/webp'
    case '.jpg':
    case '.jpeg': return 'image/jpeg'
    case '.svg': return 'image/svg+xml'
    default: return 'image/png'
  }
}
