export type Projection = {
  schema: 1
  generated_at: string
  project_uid: string
  attested_sources: ('stream' | 'capacity')[]
  stream: {
    status: 'ok' | 'corrupt' | 'absent' | 'unreadable'
    last_seq: number
    anchor: { value: number | null; relationship: 'ok' | 'lag' | 'ahead' | 'absent' }
    torn_tail: boolean
    undecodable_records: number[]
  }
  capacity: { limit: number; live: number | null; as_of: string | null }
  attention: { kind: string; agent: string | null; reason: string; since: string; attested: boolean }[]
  agents: Record<string, {
    state: 'busy' | 'idle' | 'blocked' | 'done' | 'unknown'
    since: string | null
    message: string
    stale: boolean
    attested: false
    attempt: null | {
      id: string
      decided_at: string
      decision: 'allow' | 'deny'
      open: boolean
      last: { class: string | null; stage: string | null; ended_at: string | null }
    }
  }>
  anomalies: { unregistered_logs: number; unparsable_lines: number; uid_mismatches: number; undecodable_records: number }
}

export type ProjectionResult =
  | { present: false; reason: 'missing' | 'unreadable' | 'unparsable' | 'schema' }
  | { present: true; projection: Projection; ageSeconds: number; stale: boolean }

export type ProjectionResponse = ProjectionResult & {
  uid: string | null
  generated_at: string | null
  displayNames: Record<string, string>
}
