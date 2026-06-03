<script setup lang="ts">
// Bob-Detail-Seite /team/<name> (Austin 2026-06-01): Profil-Header (RosterCard) →
// Position direkt darunter → Tabs (Heartbeats | Infos), Struktur wie der Inbox-Hub.
// key=fullPath → frischer Mount pro Bob beim Navigieren.
definePageMeta({ key: route => route.fullPath })

const route = useRoute()
const name = String(route.params.name)
const { data: standup } = await useStandup()
const agent = computed(() => ((standup.value as any)?.agents || []).find((a: any) => a.name === name)
  || { name, role: '', latest: null })
const { data: bob } = await useFetch('/api/bob', { key: `bob-${name}`, query: { name } })

const tab = ref<'hb' | 'info'>('hb')
useHead({ title: `${name} · Team · Stand-up` })
</script>

<template>
  <div>
    <div class="page-head">
      <NuxtLink to="/" class="back-link"><Icon name="mdi:arrow-left" class="ic" /> Team</NuxtLink>
    </div>

    <RosterCard :agent="agent" :show-avatar="(standup as any)?.theme?.settings?.showAvatars !== false" />

    <!-- Position direkt unter dem Profil-Header (Austin) -->
    <div class="bob-pos">
      <Icon name="mdi:clipboard-text-outline" class="ic" />
      <span>{{ bob?.description || bob?.role || '— keine Positions-Beschreibung —' }}</span>
    </div>

    <!-- Navigation: Tabs für Heartbeats + Infos (v-tabs, wie Inbox/Reports). -->
    <div class="vtabs">
      <button class="vtab" :class="{ active: tab==='hb' }" @click="tab='hb'"><Icon name="mdi:heart-pulse" class="ic" /><span class="vtab-label">Heartbeats</span></button>
      <button class="vtab" :class="{ active: tab==='info' }" @click="tab='info'"><Icon name="mdi:information-outline" class="ic" /><span class="vtab-label">Infos</span></button>
    </div>

    <HeartbeatList v-if="tab==='hb'" :agent="name" :limit="42" />
    <div v-else>
      <div v-if="bob?.html" class="md bob-md" v-html="bob.html"></div>
      <div v-else class="muted">— keine Agent-Definition für „{{ name }}" gefunden —</div>
    </div>
  </div>
</template>

<style scoped>
.back-link { display: inline-flex; align-items: center; gap: 5px; color: #8b949e; text-decoration: none; font-size: 13px; }
.back-link:hover { color: #58a6ff; }
.bob-pos { display: flex; align-items: flex-start; gap: 8px; font-size: 13px; color: #c9d1d9; margin: 0 0 6px; padding: 10px 12px; background: #161b22; border: 1px solid #21262d; border-left: 3px solid #58a6ff; border-radius: 8px; }
.bob-pos .ic { color: #58a6ff; flex: 0 0 auto; margin-top: 1px; }
.bob-md { background: #161b22; border: 1px solid #21262d; border-radius: 10px; padding: 6px 16px 14px; }
</style>
