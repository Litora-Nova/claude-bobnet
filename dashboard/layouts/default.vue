<script setup lang="ts">
// Persistente Shell für ALLE Seiten: app-bar-Header (Projektname → Link zur
// Team-Seite + dynamischer Seitentitel), Mobile-Burger, globales Blocker-Banner,
// Footer-Clock. Zentrales Live-Polling lebt hier (Layout immer gemountet).

const route = useRoute()
const demoMode = computed(() => route.query.demo === '1')
// app-bar: Projektname (Demo-Mode anonymisiert) + aktueller Seitentitel statt
// statischem "Stand-up". Projektname ist Link zur Team-Startseite.
const brandName = computed(() => demoMode.value ? 'Team' : ((useRuntimeConfig().public.brand as string) || 'Stand-up'))

// Geteilte Live-Quellen (stabile Keys → ein Cache für Layout + Seiten).
const { data: standup } = await useStandup()
await useTasks()
const { data: austinTasks } = useAustinTasks()
const blocked = useBlocked()

// Footer-Clock: explizit Europe/Berlin (SSR=UTC sonst ≠ Client). Memory binding.
const clock = computed(() => (standup.value as any)?.updatedAt
  ? new Date((standup.value as any).updatedAt).toLocaleTimeString('de-DE', { timeZone: 'Europe/Berlin', hour12: false })
  : '…')

// Briefing-Badge (offene austin.tasks). Q&A bekommt KEINEN Indikator (Austin).
const tasksOpenCount = computed(() => ((austinTasks.value as any)?.tasks || []).filter((t: any) => !t.done).length)

// Mobile-Burger (der coole bleibt). Sammel-Badge = offene Briefing-Tasks.
const burgerOpen = ref(false)
const totalOpenBadge = computed(() => tasksOpenCount.value || 0)
watch(() => route.path, () => { burgerOpen.value = false })

// Zentrales Live-Polling: schnelle Quellen 3s, Summary-Quellen 10s.
let fast: ReturnType<typeof setInterval> | undefined
let slow: ReturnType<typeof setInterval> | undefined
onMounted(() => {
  fast = setInterval(() => refreshNuxtData(['standup', 'tasks', 'inbox']), 3000)
  slow = setInterval(() => refreshNuxtData(['qa', 'austinTasks']), 10000)
})
onBeforeUnmount(() => { if (fast) clearInterval(fast); if (slow) clearInterval(slow) })

// Globale Status-Eingabe (Austin): Icon im Header, Form direkt darunter — auf
// JEDER Seite verfügbar (Austin 2026-06-01). Postet als agent=Austin → standup.
const myStatus = ref('busy')
const myMsg = ref('')
const showMentions = ref(false)
const showStatusForm = ref(false)
onMounted(() => { if (localStorage.getItem('showStatus') === '1') showStatusForm.value = true })
watch(showStatusForm, v => localStorage.setItem('showStatus', v ? '1' : '0'))
async function postStatus() {
  if (!myMsg.value.trim()) return
  await $fetch('/api/heartbeat', { method: 'POST', body: { agent: 'Austin', status: myStatus.value, msg: myMsg.value.trim() } })
  myMsg.value = ''
  refreshNuxtData('standup')
}

// Schlanke Haupt-Nav (Austin 2026-06-01): nur Team · Reports · Docs · Bugs · Inbox.
// Reports = Tabs (Sprints/Feedback/Wünsche). Inbox = Hub mit Unterseiten
// (Approvals/Briefings/Messages/Tasks); Briefing-Badge + Block-! hängen an Inbox.
const NAV = [
  { to: '/', label: 'Team', icon: 'mdi:account-group', cls: 'nav-home' },
  { to: '/reports', label: 'Reports', icon: 'mdi:file-document-outline' },
  { to: '/docs', label: 'Docs', icon: 'mdi:book-information-variant' },
  { to: '/bugs', label: 'Bugs', icon: 'mdi:bug-outline' },
  { to: '/inbox', label: 'Inbox', icon: 'mdi:inbox-arrow-down', badge: 'briefing' },
]
// Dynamischer Seitentitel für die app-bar. Unterpfade von /reports bzw. /inbox
// (Tabs/Subpages) zeigen den Parent-Namen.
const pageTitle = computed(() => {
  const hit = NAV.find(n => n.to === route.path)
  if (hit) return hit.label
  if (route.path.startsWith('/reports')) return 'Reports'
  if (route.path.startsWith('/inbox')) return 'Inbox'
  // Bob-Detail: Name des Bobs als Header-Titel (Austin 2026-06-01).
  if (route.path.startsWith('/team/')) return decodeURIComponent(route.path.slice('/team/'.length))
  return ''
})
</script>

<template>
  <div class="wrap">
    <header>
      <h1>
        <span class="title-pulse" title="live"></span>
        <NuxtLink to="/" class="brand">{{ brandName }}</NuxtLink>
        <span v-if="pageTitle" class="title-sep">·</span>
        <span v-if="pageTitle" class="page-name">{{ pageTitle }}</span>
      </h1>
      <div class="head-right">
        <!-- Status-Icon VOR der Nav (jede Größe) → Form öffnet direkt unter dem Header. -->
        <button class="status-hdr" :class="{ active: showStatusForm }" @click="showStatusForm = !showStatusForm" title="Status eintragen" aria-label="Status eintragen"><Icon name="mdi:comment-account-outline" /></button>
        <!-- Burger (≤920px) öffnet das Nav-Dropdown oben; Desktop zeigt Inline-Links. -->
        <button class="burger" :class="{ open: burgerOpen }" @click="burgerOpen = !burgerOpen" :title="burgerOpen ? 'Menü schließen' : 'Menü öffnen'" aria-label="Menü">
          <span class="bars"></span><span v-if="totalOpenBadge" class="burger-badge">{{ totalOpenBadge }}</span>
        </button>
        <nav class="head-actions" :class="{ 'menu-open': burgerOpen }">
          <NuxtLink v-for="n in NAV" :key="n.to" :to="n.to" class="ghost nav-link" :class="n.cls">
            <Icon :name="n.icon" class="nav-ic" />
            <span>{{ n.label }}</span>
            <span v-if="n.badge === 'briefing' && tasksOpenCount" class="qa-badge">{{ tasksOpenCount }}</span>
            <span v-if="n.to === '/inbox' && blocked.length" class="qa-badge blocked" :title="`${blocked.length} blockiert`">!</span>
          </NuxtLink>
        </nav>
      </div>
    </header>
    <!-- Backdrop schließt das Mobile-Menü beim Tap außerhalb -->
    <div v-if="burgerOpen" class="burger-backdrop" @click="burgerOpen = false"></div>

    <!-- Status-Form direkt unter dem Header (Toggle via Header-Icon, jede Seite). -->
    <form v-if="showStatusForm" class="me" @submit.prevent="postStatus">
      <span class="me-label"><Icon name="mdi:account-circle" class="ic" /> Dein Status</span>
      <select v-model="myStatus"><option>busy</option><option>idle</option><option>blocked</option><option>done</option></select>
      <input v-model="myMsg" placeholder="Woran arbeitest du gerade?  (@team / @dev / @Name pingt das Team)" />
      <button type="submit">Eintragen</button>
      <button type="button" class="me-info" @click="showMentions = !showMentions" title="Wen kann ich erwähnen?"><Icon name="mdi:information-outline" class="ic" /></button>
    </form>
    <div v-if="showStatusForm && showMentions" class="me-hint">Erwähnen pingt in den Team-Inbox: <b>@team</b> (alle) · <b>@dev</b> (Bill+Luke) · @Bob @Bill @Luke @Linus @Dexter @Riker @Marvin</div>

    <!-- Globales Blocker-Banner: akute 'blocked'-Agents nie übersehbar (jede Seite). -->
    <div v-if="blocked.length" class="banner">
      <Icon name="mdi:alert" class="banner-icon" />
      <span class="banner-title">{{ blocked.length }} blockiert</span>
      <span class="banner-names">{{ blocked.map((a: any) => a.name).join(', ') }}</span>
      <NuxtLink to="/inbox/tasks" class="banner-link">→ auflösen</NuxtLink>
    </div>

    <!-- page-main: min-height 70vh → kurze Seiten füllen den Viewport (kein inner-scroll). -->
    <main class="page-main"><slot /></main>

    <footer class="footer-status" :title="(standup as any)?.updatedAt || ''">live · {{ clock }}</footer>
  </div>
</template>
