import { readProjection } from '../utils/projection.mjs'
import { tenantOf } from '../utils/tenant'
import { teamOf } from '../utils/team'
import { themeOf } from '../utils/theme'

export default defineEventHandler(async (event) => {
  setHeader(event, 'Cache-Control', 'no-store')
  const tenant = tenantOf(event)
  const result = await readProjection(tenant.standupDir, new Date().toISOString())
  const displayNames: Record<string, string> = Object.create(null)
  if (result.present) {
    const theme = themeOf(tenant, teamOf(tenant))
    const uids = [...Object.keys(result.projection.agents), ...result.projection.attention.flatMap(item => item.agent === null ? [] : [item.agent])]
    for (const uid of uids) displayNames[uid] = theme.displayNameOf(uid)
  }
  return { ...result, uid: tenant.uid, generated_at: result.present ? result.projection.generated_at : null, displayNames }
})
