<script setup lang="ts">
import type { ProjectionResponse } from '~/types/projection'

const props = defineProps<{ rosterStatus: Record<string, string | null> }>()
const { data, error } = await useProjection()
const result = computed(() => error.value ? null : data.value as ProjectionResponse | null)
const snapshot = computed(() => result.value?.present ? result.value : null)
const projection = computed(() => snapshot.value?.projection)
const age = computed(() => {
  const seconds = snapshot.value?.ageSeconds ?? 0
  if (seconds < 0) return `clock ahead by ${-seconds}s`
  return `${seconds}s old`
})
const unavailable = computed(() => {
  if (error.value) return 'unknown — projection request failed'
  if (!result.value) return 'unknown — loading projection'
  if (!result.value.present && result.value.reason !== 'missing') return `unknown — projection ${result.value.reason}`
  return 'unknown — no projection published'
})
function displayName(uid: string | null) {
  if (uid === null) return 'Project'
  const mapped = result.value?.displayNames[uid]
  if (mapped && mapped !== uid) return mapped
  const prefix = `${projection.value?.project_uid}-`
  return uid.startsWith(prefix) ? uid.slice(prefix.length) : uid
}
function differs(uid: string, state: string) {
  const roster = Object.hasOwn(props.rosterStatus, uid) ? props.rosterStatus[uid] : null
  return !!roster && roster !== 'unknown' && state !== 'unknown' && roster !== state
}
const source = (attested: boolean) => attested ? 'broker-attested' : 'agent-asserted'
const observed = (name: 'stream' | 'capacity') => projection.value?.attested_sources.includes(name)
const anomalyLabels = { unregistered_logs: 'Unregistered logs', unparsable_lines: 'Unparsable lines', uid_mismatches: 'UID mismatches', undecodable_records: 'Undecodable records' }
</script>

<template>
  <section class="projection-panel" aria-labelledby="projection-title">
    <div class="projection-heading">
      <h2 id="projection-title"><Icon name="mdi:broadcast" aria-hidden="true" /> Broker view</h2>
      <template v-if="snapshot"><span>· as of <time :datetime="snapshot.projection.generated_at">{{ snapshot.projection.generated_at }}</time> ({{ age }})</span><span v-if="snapshot.stale" class="projection-pill warn"><Icon name="mdi:clock-alert-outline" aria-hidden="true" /> stale</span></template>
    </div>
    <p v-if="!projection" class="projection-muted" role="status">{{ unavailable }}</p>
    <template v-else>
      <div class="projection-overview">
        <section class="projection-block" aria-labelledby="projection-stream">
          <h3 id="projection-stream"><Icon name="mdi:broadcast" aria-hidden="true" /> Stream <span class="projection-source">{{ observed('stream') ? 'broker-attested' : 'unknown — not observed' }}</span></h3>
          <dl class="projection-facts"><div><dt>Status</dt><dd><span class="projection-pill" :class="{ good: projection.stream.status === 'ok', bad: projection.stream.status === 'corrupt' }">{{ projection.stream.status }}</span></dd></div><div><dt>Last sequence</dt><dd>{{ projection.stream.last_seq }}</dd></div><div><dt>Anchor</dt><dd>{{ projection.stream.anchor.value ?? 'unknown' }} · {{ projection.stream.anchor.relationship }}</dd></div><div><dt>Torn tail</dt><dd>{{ projection.stream.torn_tail ? 'yes' : 'no' }}</dd></div><div><dt>Undecodable records</dt><dd>{{ projection.stream.undecodable_records.length }}</dd></div></dl>
        </section>
        <section class="projection-block" aria-labelledby="projection-capacity">
          <h3 id="projection-capacity"><Icon name="mdi:gauge" aria-hidden="true" /> Capacity <span class="projection-source">{{ observed('capacity') ? 'broker-attested' : 'unknown — not observed' }}</span></h3>
          <p class="projection-capacity">{{ projection.capacity.live ?? 'unknown' }} / {{ projection.capacity.limit }} <span class="projection-muted">live</span></p>
          <meter v-if="projection.capacity.live !== null" :min="0" :max="projection.capacity.limit" :value="projection.capacity.live" :aria-valuetext="`${projection.capacity.live} live out of ${projection.capacity.limit}`" aria-label="Broker capacity" />
          <p class="projection-muted">as of <time v-if="projection.capacity.as_of" :datetime="projection.capacity.as_of">{{ projection.capacity.as_of }}</time><span v-else>unknown</span></p>
        </section>
      </div>
      <section class="projection-block" aria-labelledby="projection-attention">
        <h3 id="projection-attention"><Icon name="mdi:alert-circle-outline" aria-hidden="true" /> Attention <span class="projection-muted">{{ projection.attention.length }}</span></h3>
        <p v-if="!projection.attention.length" class="projection-muted">nothing waiting on a human — reported in this snapshot; absence is not proof that no help is needed.</p>
        <ul v-else class="projection-list"><li v-for="(item, index) in projection.attention" :key="index"><div class="projection-row"><span class="projection-pill warn">{{ item.kind }}</span><strong :title="item.agent ?? 'Project'">{{ displayName(item.agent) }}</strong><span class="projection-source">{{ source(item.attested) }}</span></div><p class="projection-text">{{ item.reason }}</p><p class="projection-muted">since <time :datetime="item.since">{{ item.since }}</time></p></li></ul>
      </section>
      <section class="projection-block" aria-labelledby="projection-agents">
        <h3 id="projection-agents"><Icon name="mdi:account-group" aria-hidden="true" /> Agents</h3>
        <p v-if="!Object.keys(projection.agents).length" class="projection-muted">No registered agents in this snapshot.</p>
        <ul v-else class="projection-list"><li v-for="(agent, uid) in projection.agents" :key="uid">
          <div class="projection-row"><strong :title="String(uid)">{{ displayName(String(uid)) }}</strong><span class="projection-pill" :class="`state-${agent.state}`">{{ agent.state }}</span><span class="projection-source">{{ source(agent.attested) }}</span><span v-if="agent.stale" class="projection-pill warn">stale heartbeat</span><span v-if="differs(String(uid), agent.state)" class="projection-pill warn"><Icon name="mdi:sync-alert" aria-hidden="true" /> differs from roster</span></div>
          <p class="projection-muted">since <time v-if="agent.since" :datetime="agent.since">{{ agent.since }}</time><span v-else>unknown</span></p>
          <p class="projection-text">{{ agent.message }}</p>
          <div v-if="agent.attempt" class="projection-attempt"><span class="projection-source">broker-attested attempt</span><p>{{ agent.attempt.id }} · {{ agent.attempt.decision }} · {{ agent.attempt.open ? 'open' : 'closed' }}</p><p class="projection-muted">decided at <time :datetime="agent.attempt.decided_at">{{ agent.attempt.decided_at }}</time></p><p>Last: {{ agent.attempt.last.class ?? 'unknown' }} · stage {{ agent.attempt.last.stage ?? 'unknown' }} · ended <time v-if="agent.attempt.last.ended_at" :datetime="agent.attempt.last.ended_at">{{ agent.attempt.last.ended_at }}</time><span v-else>unknown</span></p></div>
          <p v-else class="projection-muted">No attempt observed in this snapshot.</p>
        </li></ul>
      </section>
      <section class="projection-block" aria-labelledby="projection-anomalies"><h3 id="projection-anomalies"><Icon name="mdi:file-alert-outline" aria-hidden="true" /> Anomalies <span class="projection-source">broker-attested observations</span></h3><dl class="projection-facts"><div v-for="(label, key) in anomalyLabels" :key="key"><dt>{{ label }}</dt><dd>{{ projection.anomalies[key] }}</dd></div></dl></section>
    </template>
  </section>
</template>
