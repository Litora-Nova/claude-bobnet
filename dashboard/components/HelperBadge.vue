<script setup lang="ts">
// Icon-only Badge fuer ephemere Helfer (category==='helper': ROAMER/Sonde).
// Helfer sind KEIN Roster-Eintrag (siehe archetypes/roamer.json) — sie erscheinen
// nur als kleines Icon-Badge am Eltern-Agent (agent.parent). Mehrere Helfer am
// selben Eltern → mehrere Badges nebeneinander.
//
// Icon-Wahl: mdi-Icon nach Helfer-Art (NICHT Emoji — das ist UI-Iconografie wie
// die mdi-Icons im Rest des Dashboards, nicht die verbotene Member-als-Emoji-
// Darstellung; Member-Avatar bleibt strikt Bild). ROAMER=Spinne, Sonde=Satellit,
// alles andere = generisches Helfer-Icon. Status faerbt den Punkt im Badge.
const props = defineProps<{ helper: any }>()

const COLORS: Record<string, string> = { busy: '#3fb950', idle: '#8b949e', blocked: '#f85149', done: '#58a6ff' }
const dot = (s?: string) => COLORS[s || ''] || '#6e7681'

// id-Praefix bestimmt das Icon (RMR-… = ROAMER, SND-… = Sonde). Fallback ueber den
// (Anzeige-)Namen, dann generisch.
const icon = computed(() => {
  const id = (props.helper?.id || '').toUpperCase()
  const nm = (props.helper?.name || '').toUpperCase()
  if (id.startsWith('RMR-') || nm.includes('ROAMER')) return 'mdi:spider'
  if (id.startsWith('SND-') || nm.includes('SONDE') || nm.includes('PROBE')) return 'mdi:satellite-variant'
  return 'mdi:robot-outline'
})
const displayName = computed(() => props.helper?.displayName || props.helper?.name)
</script>

<template>
  <span class="helper-badge" :title="`${displayName}${helper.latest?.msg ? ' · ' + helper.latest.msg : ''}`">
    <Icon :name="icon" class="hb-ic" />
    <span class="hb-dot" :style="{ background: dot(helper.latest?.status) }"></span>
  </span>
</template>

<style scoped>
.helper-badge { position: relative; display: inline-flex; align-items: center; justify-content: center; width: 22px; height: 22px; border-radius: 6px; background: #0d1117; border: 1px solid #21262d; }
.hb-ic { font-size: 14px; color: #8b949e; }
.hb-dot { position: absolute; right: -2px; bottom: -2px; width: 8px; height: 8px; border-radius: 50%; border: 1.5px solid #0d1117; }
</style>
