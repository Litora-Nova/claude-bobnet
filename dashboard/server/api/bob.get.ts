import { promises as fs } from 'node:fs'
import { resolve, join } from 'node:path'
import { render, frontmatter } from '../utils/md'
import { tenantOf } from '../utils/tenant'
import { teamOf } from '../utils/team'
import { themeOf } from '../utils/theme'

// Detail-Infos zu einem Bob (für /team/<name>): Rolle (Roster) + Position/Aufgabe
// aus der Agent-Definition (.claude/agents/<name>.md, eine Ebene über standup im
// Hauptrepo). Body → HTML (Frontmatter gestrippt); description als Kurzfassung.
export default defineEventHandler(async (event) => {
  const name = String(getQuery(event).name || '').replace(/[^A-Za-z0-9_-]/g, '')
  const tenant = tenantOf(event)
  const team = teamOf(tenant)
  const theme = themeOf(tenant, team)
  const root = tenant.standupDir
  const agentsDir = resolve(root, '../.claude/agents')
  const raw = await fs.readFile(join(agentsDir, name.toLowerCase() + '.md'), 'utf8').catch(() => '')
  const { data, body } = frontmatter(raw)
  const meta = team.TEAM[name] || { role: '', order: 99 }
  return {
    name,
    displayName: theme.displayNameOf(name),
    bio: theme.bioOf(name),
    role: meta.role,
    description: data.description || '',
    html: raw ? render(body) : '',
    hasAgent: !!raw,
  }
})
