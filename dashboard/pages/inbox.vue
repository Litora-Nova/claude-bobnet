<script setup lang="ts">
// Inbox = "Meine Page"-Hub (Austin). Oben Austin-RosterCard (nur Zustand), darunter
// Sub-Nav (v-tabs) + die gewählte Unterseite. Index (/inbox) = letzte 42 Heartbeats.
const { data: standup } = await useStandup()
const { data: austinTasks } = await useAustinTasks()
// Tenant-aware (#13): ?project mitschicken UND den Cache-Key projekt-abhängig
// machen (sonst leakt approvals über Tenants — der Server fällt sonst auf das
// Launcher-Projekt zurück). Key analog zur projekt-abhängigen Quelle.
const apprProject = useActiveProject()
const { data: approvals } = await useFetch('/api/approvals', {
  key: () => `approvals-${apprProject.value || 'env'}`,
  query: useProjectQuery(),
})

const me = computed(() => ((standup.value as any)?.agents || []).find((a: any) => a.name === 'Austin')
  || { name: 'Austin', role: 'Product Owner / Vision (2-legger)', latest: null })

// Indikatoren: offene Briefings (austin.tasks nicht done) + pending Approvals.
const briefOpen = computed(() => ((austinTasks.value as any)?.tasks || []).filter((t: any) => !t.done).length)
const apprPending = computed(() => ((approvals.value as any)?.approvals || []).filter((a: any) => a.status === 'pending').length)

const SUB = computed(() => [
  { to: '/inbox', label: 'Heartbeats', icon: 'mdi:heart-pulse', badge: 0 },
  { to: '/inbox/approvals', label: 'Approvals', icon: 'mdi:check-decagram-outline', badge: apprPending.value },
  { to: '/inbox/briefings', label: 'Briefings', icon: 'mdi:clipboard-text-outline', badge: briefOpen.value },
  { to: '/inbox/tasks', label: 'Tasks', icon: 'mdi:format-list-checks', badge: 0 },
  { to: '/inbox/messages', label: 'Messages', icon: 'mdi:email-outline', badge: 0 },
])
useHead({ title: 'Inbox · Meine Page · Stand-up' })
</script>

<template>
  <div>
    <RosterCard :agent="me" tag="Meine Page" :show-avatar="(standup as any)?.theme?.settings?.showAvatars !== false" />

    <!-- Sub-Nav als v-tabs (desktop grow, mobile stacked). Echte, linkbare Routen. -->
    <nav class="vtabs">
      <NuxtLink v-for="s in SUB" :key="s.to" :to="s.to" class="vtab">
        <Icon :name="s.icon" class="ic" /><span class="vtab-label">{{ s.label }}</span>
        <span v-if="s.badge" class="vtab-badge">{{ s.badge }}</span>
      </NuxtLink>
    </nav>

    <NuxtPage />
  </div>
</template>
