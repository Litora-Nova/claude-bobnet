<script setup lang="ts">
// Team (/): Sprintbar + Team-Grid (sortierbar, Karten → /team/<name>-Detail) +
// Sprint-Detail. Status-Eingabe lebt seit 2026-06-01 global im Header (jede Seite),
// nicht mehr hier. Der PO ist nicht im Grid (er hat /inbox = "Meine Page").

const { data } = await useStandup()
// PO-Name aus der Instanz-Config (team.config po.name → public.poName), Fallback
// 'Owner' — der PO wird (als Sicherheitsnetz) aus dem Roster-Grid gefiltert.
const poName = (useRuntimeConfig().public.poName as string) || 'Owner'

const route = useRoute()
const demoMode = computed(() => route.query.demo === '1')
const rc = useRuntimeConfig()
useHead({ title: () => demoMode.value ? (rc.public.demoTitle as string) : `Team · ${rc.public.brand}` })

const COLORS: Record<string, string> = { busy: '#3fb950', idle: '#8b949e', blocked: '#f85149', done: '#58a6ff' }
const dot = (s?: string) => COLORS[s || ''] || '#6e7681'

// Avatar: BILD aus der Theme-Route (aktives Theme). HARTE Regel (PO): Mitglieder
// werden NIE per Emoji gezeigt — fehlt ein Avatar, liefert die Route das Theme-
// Default-Bild (Anonymous-/Hacker-Maske); laedt selbst das nicht, faellt der Client
// auf das statische Default-Bild. Name/Bio kommen aus dem Theme (server-seitig am Agent).
const DEFAULT_AVATAR = '/avatars/default.png'    // Anonymous-/Hacker-Maske, NIE Emoji
const fallback = reactive(new Set<string>())     // Namen, deren Theme-Avatar nicht lud
const onImgError = (name: string) => fallback.add(name)
const avatarSrc = (name: string) => avatarUrl(name)   // tenant-aware (#9): ?project=<uid> wenn aktiv
const displayName = (a: any) => a.displayName || a.name
// Theme-Setting: Bilder anzeigen ja/nein (Default ja). false = nur Name (nie Emoji).
const showAvatars = computed(() => ((data.value as any)?.theme?.settings?.showAvatars) !== false)

// Sprintbar-Text: bevorzugt die **Ziel:**-Zeile statt des "# Sprint (aktiv) — DATUM"-
// Headers (sah mobil abgeschnitten aus). Strippt Markdown-Fettung + "(Voll: …)".
const sprintLine = computed(() => {
  const lines = ((data.value as any)?.sprint || '').split('\n').map((l: string) => l.trim())
  const ziel = lines.find((l: string) => /^\*\*Ziel:\*\*/i.test(l))
  const pick = ziel
    ? ziel.replace(/^\*\*Ziel:\*\*/i, '').replace(/\(Voll:[^)]*\)/i, '')
    : (lines.find((l: string) => l && !/^#/.test(l) && !/^-{3,}/.test(l)) || lines.find(Boolean) || '')
  return pick.replace(/\*\*/g, '').trim()
})

// Team-Grid Sortierung: activity | role | name (Default activity), via localStorage.
type TeamSort = 'activity' | 'role' | 'name'
const teamSort = ref<TeamSort>('activity')
onMounted(() => { const s = localStorage.getItem('teamSort') as TeamSort | null; if (s === 'activity' || s === 'role' || s === 'name') teamSort.value = s })
watch(teamSort, v => localStorage.setItem('teamSort', v))

// "Inaktiv" = >4h kein Heartbeat. Referenz-"jetzt" = updatedAt aus der API (gleicher
// Wert SSR+Client → kein Hydration-Mismatch). Collapse NUR bei Sort=Aktivität.
const FOUR_H = 4 * 60 * 60 * 1000
const nowRef = computed(() => { const u = (data.value as any)?.updatedAt; return u ? new Date(u).getTime() : 0 })
const isInactive = (a: any) => !a.latest?.epoch || (nowRef.value - a.latest.epoch) > FOUR_H
const isCollapsed = (a: any) => teamSort.value === 'activity' && isInactive(a)
// Last-log kürzen (collapsed Name 17 / Rolle 23; Rolle-Name-Heartbeat responsiv).
const clip = (s: string, n: number) => { const t = s || ''; return t.length > n ? t.slice(0, n).trimEnd() + '…' : t }
// HARTE Zeichengrenze für den Heartbeat im Grid (PO: CSS-Truncation reicht
// mobil nicht → echtes Char-Limit). Mobile 75 / Desktop 160. winW startet auf
// Desktop (SSR), onMounted korrigiert clientseitig (Update NACH Hydration → kein
// Mismatch). resize hält es live.
const winW = ref(1200)
function onResize() { winW.value = window.innerWidth }
onMounted(() => { onResize(); window.addEventListener('resize', onResize) })
onBeforeUnmount(() => window.removeEventListener('resize', onResize))
const beatLimit = computed(() => winW.value <= 640 ? 75 : 160)

const STATUS_RANK: Record<string, number> = { busy: 4, idle: 3, blocked: 2, done: 1 }
const sortedAgents = computed(() => {
  const list = [...((data.value as any)?.agents || [])]
  if (teamSort.value === 'role') return list.sort((a: any, b: any) => a.order - b.order)
  if (teamSort.value === 'name') return list.sort((a: any, b: any) => a.name.localeCompare(b.name))
  return list.sort((a: any, b: any) => {
    const ea = a.latest?.epoch || 0, eb = b.latest?.epoch || 0
    if (ea !== eb) return eb - ea
    const sa = STATUS_RANK[a.latest?.status] || 0
    const sb = STATUS_RANK[b.latest?.status] || 0
    if (sa !== sb) return sb - sa
    return a.order - b.order
  })
})
// Category-getriebene Aufteilung (kein Hardcode — category kommt aus dem Archetyp,
// pro Member in team.config ueberschreibbar; siehe server/utils/team.ts):
//   bob/coworker → Team-Grid (Roster). coworker = externer Mensch-getriebener
//     (Tim/Henry), war schon immer im Grid mit "ext"-Badge → bleibt wie gehabt.
//   service      → eigene Service-Leiste (GUPPI/SCUT/Colonel, cross-project).
//   helper       → KEIN eigener Eintrag; Icon-Badge am Eltern-Agent (parent).
//   human (PO)   → gar nicht im Grid (hat /inbox). Der PO-Namens-Sonderfall bleibt
//                  als Sicherheitsnetz fuer id-/category-lose Alt-Configs.
const catOf = (a: any): string => a.category || 'bob'
const ROSTER_CATS = new Set(['bob', 'coworker'])
const visibleAgents = computed(() => sortedAgents.value.filter((a: any) =>
  ROSTER_CATS.has(catOf(a)) && a.name !== poName))
const serviceAgents = computed(() => sortedAgents.value.filter((a: any) => catOf(a) === 'service'))
// Helfer je Eltern-Agent gruppiert (Badge-Rendering im Roster-Card).
const helpersByParent = computed(() => {
  const m: Record<string, any[]> = {}
  for (const a of sortedAgents.value) {
    if (catOf(a) !== 'helper' || !a.parent) continue
    ;(m[a.parent] ||= []).push(a)
  }
  return m
})
const helpersFor = (a: any) => helpersByParent.value[a.name] || []

// Sprintbar-Info-Button → scrollt zur Sprint-Detail-Section unten.
const sprintRef = ref<HTMLElement | null>(null)
function scrollToSprint() { sprintRef.value?.scrollIntoView({ behavior: 'smooth', block: 'start' }) }
</script>

<template>
  <div>
    <div v-if="sprintLine" class="sprintbar">
      <span class="sb-text"><Icon name="mdi:run" class="sb-ic" /> {{ sprintLine }}</span>
      <button class="sb-info" @click="scrollToSprint" title="Volles Sprint-Ziel + Details unten anzeigen"><Icon name="mdi:information-outline" class="ic" /> Details</button>
    </div>

    <div class="team-sort">
      <Icon name="mdi:sort" class="ts-icon" title="Sortieren" />
      <button class="chip" :class="{ active: teamSort==='activity' }" @click="teamSort='activity'" title="Neueste Aktivität zuerst">Aktivität</button>
      <button class="chip" :class="{ active: teamSort==='role' }"     @click="teamSort='role'"     title="Reihenfolge gem. TEAM.md">Rolle</button>
      <button class="chip" :class="{ active: teamSort==='name' }"     @click="teamSort='name'"     title="Alphabetisch">Name</button>
    </div>
    <!-- Service-Leiste (cross-project Dienste: GUPPI/SCUT/Colonel). BobNet-optional:
         leere Leiste wird ausgeblendet (v-if). -->
    <div v-if="serviceAgents.length" class="services">
      <span class="svc-label"><Icon name="mdi:server-network" class="ic" /> Services</span>
      <ServiceStatus v-for="s in serviceAgents" :key="s.name" :agent="s" :now-ref="nowRef" :show-avatar="showAvatars" />
    </div>

    <div class="grid">
      <NuxtLink class="member" :class="{ inactive: isCollapsed(a), byjob: teamSort !== 'activity' }" :title="isCollapsed(a) ? 'inaktiv — >4h kein Heartbeat' : `${a.name} — Details`" :to="`/team/${a.name}`" v-for="a in visibleAgents" :key="a.name">
        <div class="ava" v-if="showAvatars">
          <img v-if="!fallback.has(a.name)" :src="avatarSrc(a.name)" :alt="displayName(a)" @error="onImgError(a.name)" />
          <img v-else :src="DEFAULT_AVATAR" :alt="displayName(a)" />
          <span class="sdot" :style="{ background: dot(a.latest?.status) }" :title="a.latest?.status || 'unbekannt'"></span>
        </div>
        <div class="who">
          <div class="nm">{{ isCollapsed(a) ? clip(displayName(a), 17) : displayName(a) }}<span v-if="a.external" class="ext-badge" title="externer Co-Worker (eigener Claude-Kontext)">ext</span><span v-if="helpersFor(a).length" class="helpers" @click.prevent><HelperBadge v-for="h in helpersFor(a)" :key="h.name" :helper="h" /></span></div>
          <div class="role">{{ isCollapsed(a) ? clip(a.role, 23) : a.role }}</div>
          <!-- Sort Rolle/Name: Heartbeat kompakt unter der Rolle (1 Zeile, gedimmt). -->
          <div v-if="teamSort !== 'activity' && a.latest" class="role-beat" :title="a.latest.msg"><span class="ts">{{ a.latest.ts }}</span> <b :style="{ color: dot(a.latest.status) }">{{ a.latest.status }}</b> · {{ clip(a.latest.msg, beatLimit) }}</div>
        </div>
        <!-- Rechte Heartbeat-Spalte nur bei Sort=Aktivität (sonst unter der Rolle). -->
        <div class="beats" v-if="teamSort === 'activity'">
          <div v-if="a.latest" class="now"><span class="ts">{{ a.latest.ts }}</span> <b :style="{ color: dot(a.latest.status) }">{{ a.latest.status }}</b> · {{ clip(a.latest.msg, beatLimit) }}</div>
          <div v-else class="now muted">— idle · noch kein Heartbeat —</div>
        </div>
      </NuxtLink>
    </div>

    <!-- Sprint-Body: serverseitig gerenderter Markdown (sprintHtml aus standup.get.ts). -->
    <section class="sprint" ref="sprintRef">
      <h3 class="sprint-h"><Icon name="mdi:run" class="ic" /> Sprint-Ziel · Details</h3>
      <div v-if="(data as any)?.sprintHtml" class="md sprint-md" v-html="(data as any).sprintHtml"></div>
      <div v-else class="muted">— kein Sprint-Ziel hinterlegt —</div>
    </section>
  </div>
</template>

<style scoped>
.ts-icon { color: #6e7681; font-size: 16px; flex: 0 0 auto; }
/* Sprint-Icon: minimal größer + Farbe wie der Details-Button (amber #d29922). */
.sb-ic { color: #d29922; font-size: 17px; vertical-align: -0.18em; }
/* Service-Leiste: cross-project Dienste als Pillen-Reihe. Nur sichtbar wenn nicht
   leer (v-if im Template) — BobNet-optional. */
.services { display: flex; flex-wrap: wrap; align-items: center; gap: 8px; margin: 0 0 14px; }
.svc-label { display: inline-flex; align-items: center; gap: 5px; font-size: 11px; font-weight: 700; text-transform: uppercase; letter-spacing: .04em; color: #6e7681; margin-right: 2px; }
.svc-label .ic { font-size: 14px; }
/* Helfer-Badges: Icon-only Reihe neben dem Namen im Roster-Card. */
.helpers { display: inline-flex; align-items: center; gap: 4px; margin-left: 8px; vertical-align: middle; }
</style>
