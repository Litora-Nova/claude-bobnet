<script setup lang="ts">
// Geteilte Roster-Kachel (Avatar + Name + Rolle + Zustands-Pille). Genutzt vom
// Inbox-Hub ("Meine Page") und der Bob-Detail-Seite /team/<name>. Nur Zustand,
// kein Heartbeat-Text (der lebt in der Heartbeats-Liste).
const props = defineProps<{ agent: any; tag?: string; showAvatar?: boolean }>()
const COLORS: Record<string, string> = { busy: '#3fb950', idle: '#8b949e', blocked: '#f85149', done: '#58a6ff' }
const dot = (s?: string) => COLORS[s || ''] || '#6e7681'
// Anzeigename kommt aus dem aktiven Theme (server-seitig am Agent); kein hardcoded
// Roster. Avatar aus der Theme-Route. HARTE Regel (Austin): NIE Emoji — laedt das
// Theme-Bild nicht, kommt das statische Default-Bild (Anonymous-/Hacker-Maske).
const fail = ref(false)
const displayName = computed(() => props.agent?.displayName || props.agent?.name)
const DEFAULT_AVATAR = '/avatars/default.png'
</script>

<template>
  <div class="me-card">
    <div class="ava" v-if="showAvatar !== false">
      <img v-if="!fail" :src="avatarUrl(agent.name)" :alt="displayName" @error="fail = true" />
      <img v-else :src="DEFAULT_AVATAR" :alt="displayName" />
      <span class="sdot" :style="{ background: dot(agent.latest?.status) }" :title="agent.latest?.status || 'unbekannt'"></span>
    </div>
    <div class="who">
      <div class="nm">{{ displayName }} <span v-if="tag" class="me-tag">{{ tag }}</span></div>
      <div class="role">{{ agent.role }}</div>
    </div>
    <span class="me-state" :style="{ color: dot(agent.latest?.status), borderColor: dot(agent.latest?.status) + '66' }">
      <span class="me-state-dot" :style="{ background: dot(agent.latest?.status) }"></span>{{ agent.latest?.status || 'offline' }}
    </span>
  </div>
</template>

<style scoped>
.me-card { display: flex; align-items: center; gap: 14px; background: #161b22; border: 1px solid #21262d; border-radius: 10px; padding: 12px 14px; margin: 8px 0 12px; }
.ava { position: relative; flex: 0 0 auto; width: 52px; height: 52px; }
.ava img { width: 52px; height: 52px; border-radius: 10px; object-fit: cover; background: #0d1117; }
.ava .sdot { position: absolute; right: -3px; bottom: -3px; width: 13px; height: 13px; border-radius: 50%; border: 2px solid #161b22; }
.who { flex: 0 0 auto; min-width: 140px; }
.nm { font-size: 18px; font-weight: 700; color: #e6edf3; display: inline-flex; align-items: center; gap: 8px; }
.me-tag { font-size: 10px; font-weight: 700; letter-spacing: .04em; text-transform: uppercase; color: #58a6ff; background: #161f2e; border: 1px solid #1f6feb44; border-radius: 5px; padding: 1px 6px; }
.role { font-size: 11px; color: #8b949e; text-transform: uppercase; letter-spacing: .03em; margin-top: 3px; }
.me-state { margin-left: auto; flex: 0 0 auto; display: inline-flex; align-items: center; gap: 6px; font-size: 12px; font-weight: 700; text-transform: uppercase; letter-spacing: .03em; border: 1px solid; border-radius: 999px; padding: 4px 11px; }
.me-state-dot { width: 8px; height: 8px; border-radius: 50%; }
@media (max-width: 640px) {
  .me-card { flex-wrap: wrap; gap: 10px 12px; }
  .me-state { margin-left: 0; }
}
</style>
