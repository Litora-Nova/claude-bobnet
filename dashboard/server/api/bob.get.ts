import { promises as fs } from 'node:fs'
import { resolve, join } from 'node:path'
import { render, frontmatter } from '../utils/md'
import { TEAM } from '../utils/team'
import { displayNameOf, bioOf } from '../utils/theme'

// Detail-Infos zu einem Bob (für /team/<name>): Rolle (Roster) + Position/Aufgabe
// aus der Agent-Definition (.claude/agents/<name>.md, eine Ebene über standup im
// Hauptrepo). Body → HTML (Frontmatter gestrippt); description als Kurzfassung.
export default defineEventHandler(async (event) => {
  const name = String(getQuery(event).name || '').replace(/[^A-Za-z0-9_-]/g, '')
  const cfg = useRuntimeConfig()
  const root = resolve(process.cwd(), cfg.standupDir as string)
  const agentsDir = resolve(root, '../.claude/agents')
  const raw = await fs.readFile(join(agentsDir, name.toLowerCase() + '.md'), 'utf8').catch(() => '')
  const { data, body } = frontmatter(raw)
  const meta = TEAM[name] || { role: '', order: 99 }
  return {
    name,
    displayName: displayNameOf(name),
    bio: bioOf(name),
    role: meta.role,
    description: data.description || '',
    html: raw ? render(body) : '',
    hasAgent: !!raw,
  }
})
