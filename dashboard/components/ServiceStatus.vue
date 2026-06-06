<script setup lang="ts">
// Service-Pille fuer die Service-Leiste (category==='service'): cross-project
// Dienste mit eigenem Takt (GUPPI/SCUT/Colonel). Zeigt alive/dead statt der
// vollen busy/idle/blocked/done-Skala — ein Dienst ist nur "laeuft" oder "down".
// alive = frischer Heartbeat (<= aliveMs, Default 4h, gleiche Schwelle wie das
// Grid-"inaktiv"). nowRef kommt vom Aufrufer (updatedAt der API → kein
// Hydration-Mismatch). HARTE Regel (Austin): Avatar = Bild, NIE Emoji — laedt das
// Theme-Bild nicht, kommt das statische Default-Bild (Anonymous-/Hacker-Maske).
const props = withDefaults(defineProps<{ agent: any; nowRef?: number; aliveMs?: number; showAvatar?: boolean }>(), {
  nowRef: 0,
  aliveMs: 4 * 60 * 60 * 1000,
  showAvatar: true,
})

const DEFAULT_AVATAR = '/avatars/default.png'   // Anonymous-/Hacker-Maske, NIE Emoji
const fail = ref(false)
const displayName = computed(() => props.agent?.displayName || props.agent?.name)
const epoch = computed(() => props.agent?.latest?.epoch || 0)
// alive: Heartbeat existiert UND ist juenger als aliveMs (relativ zum API-now).
const alive = computed(() => !!epoch.value && props.nowRef > 0 && (props.nowRef - epoch.value) <= props.aliveMs)
const aliveColor = computed(() => alive.value ? '#3fb950' : '#6e7681')
const aliveLabel = computed(() => alive.value ? 'alive' : 'dead')
</script>

<template>
  <NuxtLink class="svc" :class="{ dead: !alive }" :to="`/team/${agent.name}`" :title="`${displayName} — ${aliveLabel}${agent.latest?.msg ? ' · ' + agent.latest.msg : ''}`">
    <span v-if="showAvatar" class="svc-ava">
      <img v-if="!fail" :src="avatarUrl(agent.name)" :alt="displayName" @error="fail = true" />
      <img v-else :src="DEFAULT_AVATAR" :alt="displayName" />
    </span>
    <span class="svc-dot" :style="{ background: aliveColor }"></span>
    <span class="svc-nm">{{ displayName }}</span>
    <span class="svc-role">{{ agent.role }}</span>
  </NuxtLink>
</template>

<style scoped>
.svc { display: inline-flex; align-items: center; gap: 8px; background: #161b22; border: 1px solid #21262d; border-radius: 999px; padding: 5px 12px 5px 6px; text-decoration: none; color: #e6edf3; transition: border-color .12s; }
.svc:hover { border-color: #30363d; }
.svc.dead { opacity: .62; }
.svc-ava { flex: 0 0 auto; width: 24px; height: 24px; }
.svc-ava img { width: 24px; height: 24px; border-radius: 50%; object-fit: cover; background: #0d1117; display: block; }
.svc-dot { flex: 0 0 auto; width: 9px; height: 9px; border-radius: 50%; }
.svc-nm { font-size: 13px; font-weight: 700; }
.svc-role { font-size: 11px; color: #8b949e; text-transform: uppercase; letter-spacing: .03em; }
@media (max-width: 640px) {
  .svc-role { display: none; }
}
</style>
