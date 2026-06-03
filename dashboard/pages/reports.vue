<script setup lang="ts">
// /reports — EINE Seite mit Tabs (Sprints / Feedback / Wünsche), kein Dropdown in
// der Haupt-Nav (Austin 2026-06-01). Jeder Tab hostet das generische OverlayPanel
// im page-Mode. Tab ist über ?tab= linkbar (z.B. /reports?tab=feedback).
const route = useRoute()
const router = useRouter()

const TABS = [
  { key: 'reports', label: 'Sprints', icon: 'mdi:run' },
  { key: 'feedback', label: 'Feedback', icon: 'mdi:message-text-outline' },
  { key: 'wishes', label: 'Wünsche', icon: 'mdi:star-outline' },
] as const
type TabKey = typeof TABS[number]['key']

const activeTab = computed<TabKey>(() => {
  const q = String(route.query.tab || 'reports')
  return (['reports', 'feedback', 'wishes'].includes(q) ? q : 'reports') as TabKey
})
function setTab(key: TabKey) {
  router.replace({ query: key === 'reports' ? {} : { tab: key } })
}

const tabLabel = computed(() => TABS.find(t => t.key === activeTab.value)?.label || 'Sprints')
useHead({ title: () => `Reports · ${tabLabel.value} · Stand-up` })
</script>

<template>
  <div>
    <div class="vtabs">
      <button v-for="t in TABS" :key="t.key" class="vtab" :class="{ active: activeTab === t.key }" @click="setTab(t.key)">
        <Icon :name="t.icon" class="ic" /><span class="vtab-label">{{ t.label }}</span>
      </button>
    </div>
    <!-- :key erzwingt frisches OverlayPanel pro Tab (lädt die richtige Sorte). -->
    <OverlayPanel :key="activeTab" :kind="activeTab" />
  </div>
</template>
