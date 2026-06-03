<script setup lang="ts">
// Geteilte Heartbeat-Liste (letzte N Logs eines Agents, neueste zuerst). Genutzt
// vom Inbox-Index (Austin) und der Bob-Detail-Seite. Quelle: /api/heartbeats.
const props = defineProps<{ agent: string; limit?: number }>()
const { data } = await useFetch('/api/heartbeats', {
  key: `hb-${props.agent}`,
  query: { agent: props.agent, limit: props.limit || 42 },
})
const COLORS: Record<string, string> = { busy: '#3fb950', idle: '#8b949e', blocked: '#f85149', done: '#58a6ff' }
const dot = (s?: string) => COLORS[s || ''] || '#6e7681'
const clean = (s: string) => (s || '').replace(/\*\*/g, '')   // **bold**-Marker für die Log-Ansicht strippen
</script>

<template>
  <ul class="hb-list">
    <li v-for="(b, i) in (data as any)?.beats" :key="i" class="hb">
      <span class="hb-when"><span v-if="b.date" class="hb-date">{{ b.date }}</span> {{ b.time }}</span>
      <span class="hb-status" :style="{ color: dot(b.status) }">{{ b.status }}</span>
      <span class="hb-msg">{{ clean(b.msg) }}</span>
    </li>
    <li v-if="!(data as any)?.beats?.length" class="muted">— noch keine Heartbeats —</li>
  </ul>
</template>

<style scoped>
.hb-list { list-style: none; margin: 8px 0 22px; padding: 0; display: flex; flex-direction: column; gap: 2px; }
.hb { display: flex; align-items: baseline; gap: 10px; padding: 6px 10px; border-radius: 7px; }
.hb:nth-child(odd) { background: #0d1117; }
.hb-when { flex: 0 0 auto; color: #6e7681; font-size: 12px; font-family: ui-monospace, SFMono-Regular, Menlo, monospace; min-width: 118px; }
.hb-date { color: #8b949e; }
.hb-status { flex: 0 0 auto; font-weight: 600; font-size: 12px; min-width: 54px; }
.hb-msg { flex: 1; min-width: 0; color: #c9d1d9; overflow-wrap: anywhere; }
@media (max-width: 640px) {
  .hb { flex-wrap: wrap; gap: 4px 10px; }
  .hb-msg { flex: 1 1 100%; }
}
</style>
