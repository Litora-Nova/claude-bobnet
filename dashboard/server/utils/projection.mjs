// Read-only consumer of CONTRACT-visibility schema 1. No file or result cache:
// the producer atomically replaces the file (often reached through a symlink).
import { readFile } from 'node:fs/promises'
import { join } from 'node:path'

const object = v => v !== null && typeof v === 'object' && !Array.isArray(v)
const string = v => typeof v === 'string'
const bool = v => typeof v === 'boolean'
const count = v => Number.isSafeInteger(v) && v >= 0
const nullable = check => v => v === null || check(v)
const oneOf = values => v => values.includes(v)
const arrayOf = check => v => Array.isArray(v) && v.every(check)
const fields = shape => v => object(v) && Object.entries(shape).every(([key, check]) => Object.hasOwn(v, key) && check(v[key]))

// Require an explicit offset and a real calendar date; Date.parse alone accepts
// local timestamps and normalizes impossible days such as February 30.
const instant = v => {
  if (!string(v)) return false
  const match = /^(\d{4})-(\d{2})-(\d{2})T([01]\d|2[0-3]):([0-5]\d):([0-5]\d)(?:\.\d+)?(?:Z|[+-](?:[01]\d|2[0-3]):[0-5]\d)$/.exec(v)
  if (!match || !Number.isFinite(Date.parse(v))) return false
  const [, year, month, day] = match
  const date = new Date(`${year}-${month}-${day}T00:00:00Z`)
  return date.getUTCFullYear() === Number(year) && date.getUTCMonth() + 1 === Number(month) && date.getUTCDate() === Number(day)
}

const attempt = fields({
  id: string, decided_at: instant, decision: oneOf(['allow', 'deny']), open: bool,
  last: fields({
    class: nullable(oneOf(['ok', 'provider-failure', 'timeout', 'io-refused', 'aborted'])),
    stage: nullable(oneOf(['confine', 'cwd', 'exec', 'provider', 'transport'])),
    ended_at: nullable(instant),
  }),
})
const agent = fields({
  state: oneOf(['busy', 'idle', 'blocked', 'done', 'unknown']), since: nullable(instant),
  message: string, stale: bool, attested: v => v === false, attempt: nullable(attempt),
})
const schema1 = fields({
  schema: v => v === 1, generated_at: instant, project_uid: string,
  attested_sources: arrayOf(oneOf(['stream', 'capacity'])),
  stream: fields({
    status: oneOf(['ok', 'corrupt', 'absent', 'unreadable']), last_seq: count,
    anchor: fields({ value: nullable(count), relationship: oneOf(['ok', 'lag', 'ahead', 'absent']) }),
    torn_tail: bool, undecodable_records: arrayOf(count),
  }),
  capacity: fields({ limit: v => count(v) && v > 0, live: nullable(count), as_of: nullable(instant) }),
  attention: arrayOf(fields({
    kind: oneOf(['human', 't4', 'approval', 'conflict', 'input', 'other', 'stream_unhealthy', 'presumed_dead', 'disagreement']),
    agent: nullable(string), reason: string, since: instant, attested: bool,
  })),
  agents: v => object(v) && Object.values(v).every(agent),
  anomalies: fields({ unregistered_logs: count, unparsable_lines: count, uid_mismatches: count, undecodable_records: count }),
})

/**
 * @param {string} standupDir
 * @param {string} nowIso
 * @returns {Promise<import('../../types/projection').ProjectionResult>}
 */
export async function readProjection(standupDir, nowIso) {
  let raw
  try { raw = await readFile(join(standupDir, '_projection.json')) }
  catch (error) { return { present: false, reason: error.code === 'ENOENT' ? 'missing' : 'unreadable' } }
  let projection
  try { projection = JSON.parse(new TextDecoder('utf-8', { fatal: true }).decode(raw)) }
  catch { return { present: false, reason: 'unparsable' } }
  if (!schema1(projection)) return { present: false, reason: 'schema' }
  const ageSeconds = Math.floor((Date.parse(nowIso) - Date.parse(projection.generated_at)) / 1000)
  const configured = process.env.NUXT_PROJECTION_STALE_SECONDS
  const threshold = configured && /^\d+$/.test(configured) && Number.isSafeInteger(Number(configured)) ? Number(configured) : 60
  return { present: true, projection, ageSeconds, stale: ageSeconds > threshold }
}
