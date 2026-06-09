<script setup lang="ts">
// Generisches Overlay-Panel für Reports / Feedback / Wünsche / Q&A / Tasks.
// UX 1:1 wie bisher beim Report-Overlay: Liste ↔ Detail im selben Panel.
//
// kind = 'reports' | 'feedback' | 'wishes' | 'qa' | 'tasks'
//   - reports:  Liste [date · sprint · duration]   Detail = HTML
//   - feedback: Liste [date · preview · #agents]   Detail = HTML (mit MD→HTML
//               byQuestion-Aggregation für Listen/Tabellen pro Antwort)
//   - wishes:   Liste [status · prio · title · author→target]   Detail = HTML + Status-Toggle
//   - qa:       Inline-Karten (kein Detail-Drilldown nötig, Antwort ist meist kurz)
//               mit „Okay, kann weg"-Dismiss-Button, Filter Offen | Archiv.
//   - tasks:    PO-Tasks-mit-Details aus standup/po.tasks.md (Legacy: austin.tasks.md)
//               (`## <Titel>` + Markdown-Body) — Click-Expand inline, Done-State
//               via `~~strike~~` / `- [x]` / ARCHIV-Block, Filter Offen|Done|Alle.

// Wird nur noch als eigene Seite gehostet (pages/reports.vue, docs.vue,
// inbox/briefings.vue) — kein Overlay/Modal mehr, daher kein Schließen-/Dashboard-Button.
const props = defineProps<{ kind: 'reports' | 'feedback' | 'wishes' | 'qa' | 'tasks' }>()

// Tenant-aware (#13/#25): ALLE Calls hier laufen imperativ über $fetch — der
// GET load() (reports/feedback/wishes/qa/po-tasks) UND die POSTs (wishes ×2,
// qa). Die Server-Endpoints sind tenantOf-gescoped → ohne aktiven ?project liest
// load() aus dem Launcher-Projekt (FALSCHER Tenant) und die POSTs schreiben dort
// hin. projectParam() ist eine Snapshot-Funktion auf das aktive Projekt: jeder
// Call (auch der 5s-Polling-load) liest das AKTUELL aktive Projekt zur Laufzeit.
const projectParam = useProjectParam()   // () => {} oder { project }

const ENDPOINTS: Record<string, string> = {
  reports: '/api/report',
  feedback: '/api/feedback',
  wishes: '/api/wishes',
  qa: '/api/qa',
  tasks: '/api/po-tasks',
}
const TITLES: Record<string, string> = {
  reports: 'Reports',
  feedback: 'Feedback',
  wishes: 'Wünsche',
  qa: 'Docs',
  tasks: 'PO-Tasks (mit Details)',
}
// Passend zu den Nav-Icons (layouts/default.vue) — gleiche mdi-Glyphen.
const TITLE_ICON: Record<string, string> = {
  reports: 'mdi:file-document-outline',
  feedback: 'mdi:message-text-outline',
  wishes: 'mdi:star-outline',
  qa: 'mdi:book-information-variant',
  tasks: 'mdi:clipboard-text-outline',
}
const EMPTY: Record<string, string> = {
  reports: '— noch keine Reports —',
  feedback: '— noch kein Feedback gesammelt —',
  wishes: '— noch keine Wünsche —',
  qa: 'Keine offenen Fragen — schick Bob welche!',
  tasks: '— keine Tasks in po.tasks.md —',
}

const data = ref<any>(null)
const wishFilter = ref<'open' | 'all' | 'done'>('open')
// Q&A: 'open' = nicht-dismissed (Default), 'archive' = nur dismissed, 'all' = beides.
const qaFilter = ref<'open' | 'archive' | 'all'>('open')
// Tasks: 'open' = nicht-done, 'done' = nur done, 'all' = beides.
const taskFilter = ref<'open' | 'done' | 'all'>('open')
// Welche Task-IDs sind aufgeklappt (Click-Expand inline). Set überlebt Reload nicht
// bewusst — der PO will pro Session frisch entscheiden was er aufmacht.
const expandedTasks = ref<Set<number>>(new Set())
// Card-DOM-Refs damit die aufgeklappte Card beim Open in den View scrollt
// (PO 02:35: Layout-Bug — aufgeklappte Box "quetschte" andere; jetzt:
// Container scrollt nicht mehr per max-height, aber wenn der User auf eine
// Card weiter unten klickt, scrollt sie sich oben in den Viewport).
const taskCardRefs = reactive<Record<number, HTMLElement>>({})
function toggleTask(id: number) {
  const s = new Set(expandedTasks.value)
  const wasOpen = s.has(id)
  if (wasOpen) s.delete(id); else s.add(id)
  expandedTasks.value = s
  if (!wasOpen) nextTick(() => taskCardRefs[id]?.scrollIntoView({ behavior: 'smooth', block: 'start' }))
}
// Feedback-Detail kann nach Agent (Default, html) oder nach Frage gruppiert werden.
const fbGroup = ref<'agent' | 'question'>('agent')
// Feedback-Listen-Filter: Alle | nur Sprint-Runden | nur sonstige Reports |
// nach Author. Hilft bei vielen Files am gleichen Tag.
const fbFilter = ref<'all' | 'rounds' | 'other'>('all')
const fbAuthor = ref<string>('')

// Type-Badge-Farben (heuristisch, fällt auf grau zurück).
const TYPE_COLOR: Record<string, string> = {
  'round': '#58a6ff', 'round-am': '#58a6ff', 'round-eve': '#58a6ff', 'round-pm': '#58a6ff',
  'quality-check': '#d29922',
  'live-bugs': '#f85149',
  'coverage-audit': '#3fb950',
}
const typeColor = (t: string) => TYPE_COLOR[t] || '#8b949e'
const typeLabel = (t: string) => {
  if (t === 'round') return 'Sprint-Runde'
  if (t.startsWith('round-')) return 'Sprint-Runde · ' + t.slice(6)
  return t.replace(/-/g, ' ')
}

// Sehr kleiner Inline-MD-Renderer für die Aggregations-Antworten:
// escape + `code` + **bold** + Zeilenumbruch → <br/>. Reicht für unsere
// kurzen Frage-Antworten; volle Markdown-Sektionen laufen weiter über den
// Server-Render in `html`.
function inline(s: string): string {
  return s
    .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
    .replace(/`([^`]+)`/g, '<code>$1</code>')
    .replace(/\*\*([^*]+)\*\*/g, '<strong>$1</strong>')
    .replace(/\n/g, '<br/>')
}

// Liste der Einträge (kind-spezifischer Key im Response).
const items = computed<any[]>(() => {
  if (!data.value) return []
  if (props.kind === 'reports') return data.value.reports || []
  if (props.kind === 'feedback') {
    let r = (data.value.rounds || []) as any[]
    if (fbFilter.value === 'rounds') r = r.filter(x => x.kind === 'round')
    else if (fbFilter.value === 'other') r = r.filter(x => x.kind !== 'round')
    if (fbAuthor.value) r = r.filter(x => x.author === fbAuthor.value)
    return r
  }
  if (props.kind === 'qa') {
    const all = (data.value.items || []) as any[]
    if (qaFilter.value === 'all') return all
    if (qaFilter.value === 'archive') return all.filter(x => x.dismissed)
    return all.filter(x => !x.dismissed)
  }
  if (props.kind === 'tasks') {
    const all = (data.value.tasks || []) as any[]
    if (taskFilter.value === 'all') return all
    if (taskFilter.value === 'done') return all.filter(x => x.done)
    return all.filter(x => !x.done)
  }
  const w = (data.value.wishes || []) as any[]
  if (wishFilter.value === 'all') return w
  if (wishFilter.value === 'done') return w.filter(x => x.status === 'done' || x.status === 'dropped')
  return w.filter(x => x.status !== 'done' && x.status !== 'dropped')
})

async function load(file?: string) {
  // cache:'no-store' verhindert Browser-Disk-Cache trotz no-store-Header
  // vom Server (PO 02:35: Wünsche + Briefing zeigten alte Daten — der
  // Server lieferte frisch, der Browser cachte). Polling 5s siehe onMounted.
  data.value = await $fetch(ENDPOINTS[props.kind], {
    params: { ...(file ? { file } : {}), ...projectParam() },
    cache: 'no-store',
  })
}

async function toggleStatus(file: string) {
  await $fetch('/api/wishes', { method: 'POST', query: projectParam(), body: { action: 'toggle-status', file } })
  // ggf. im Detail bleiben: erneut laden inkl. file
  const f = data.value?.current?.file
  await load(f)
}

// Q&A: dismiss / undismiss — Frontmatter-Patch via /api/qa, dann Liste neu laden.
// (Kein localStorage — der PO nutzt das Dashboard auf mehreren Geräten, daher
//  Server-persistiert.)
async function qaDismiss(file: string, dismiss: boolean) {
  await $fetch('/api/qa', { method: 'POST', query: projectParam(), body: { action: dismiss ? 'dismiss' : 'undismiss', file } })
  await load()
}

// Q&A-Karten collapsible: Frage immer sichtbar, Antwort/Details eingeklappt
// (PO: Anleitungs-/Info-Seite, scanbar halten, Details auf Klick).
const qaOpen = ref<Set<string>>(new Set())
function toggleQa(file: string) {
  const s = new Set(qaOpen.value)
  if (s.has(file)) s.delete(file); else s.add(file)
  qaOpen.value = s
}
// "Ausblenden" weniger present (nur im aufgeklappten Detail) + Bestätigung,
// damit nichts aus Versehen verschwindet (PO-Wunsch).
async function qaDismissConfirm(file: string) {
  if (typeof window !== 'undefined' && !window.confirm('Diese Q&A-Karte ausblenden? Sie bleibt im Archiv abrufbar.')) return
  await qaDismiss(file, true)
}

// Submit-Form für neue Wünsche (nur ✨ Wünsche, nur Listenansicht).
// Author/Target-Liste config-getrieben statt hardcoded: PO-Name (public.poName,
// Fallback 'Owner') + die real vorhandenen Roster-Mitglieder aus dem Standup —
// so kennt die Engine keine festen Personennamen mehr und jede Instanz zeigt ihr
// echtes Team. PO steht immer vorn.
const poName = (useRuntimeConfig().public.poName as string) || 'Owner'
const { data: standupData } = useStandup()
const TEAM = computed<string[]>(() => {
  const names = ((standupData.value as any)?.agents || []).map((a: any) => a.name).filter(Boolean)
  return [poName, ...names.filter((n: string) => n !== poName)]
})
const formOpen = ref(false)
const fAuthor = ref(poName)
const fTarget = ref('team')
const fPrio = ref<'low' | 'med' | 'high'>('med')
const fTitle = ref('')
const fBody = ref('')
const fBusy = ref(false)

async function submitWish() {
  if (!fTitle.value.trim() || fBusy.value) return
  fBusy.value = true
  try {
    await $fetch('/api/wishes', {
      method: 'POST',
      query: projectParam(),
      body: {
        action: 'add',
        author: fAuthor.value, target: fTarget.value,
        priority: fPrio.value, title: fTitle.value.trim(), body: fBody.value.trim(),
      },
    })
    fTitle.value = ''; fBody.value = ''
    formOpen.value = false
    await load()
  } finally { fBusy.value = false }
}

// Author-Dropdown speist sich aus dem aktuellen Datensatz (nur Authors, die
// in mindestens einem File vorkommen — sonst leerer Wert).
const fbAuthors = computed<string[]>(() => {
  if (props.kind !== 'feedback') return []
  const set = new Set<string>()
  for (const r of (data.value?.rounds || []) as any[]) if (r.author) set.add(r.author)
  return [...set].sort()
})

const PRIO_COLOR: Record<string, string> = { high: '#f85149', med: '#d29922', low: '#6e7681' }
const STATUS_COLOR: Record<string, string> = { open: '#58a6ff', in_progress: '#d29922', done: '#3fb950', dropped: '#6e7681' }
const STATUS_LABEL: Record<string, string> = { open: 'offen', in_progress: 'läuft', done: 'fertig', dropped: 'verworfen' }

// Polling solange das Overlay offen ist: Wünsche/Briefing/Reports/Feedback
// ändern sich aus dem Hauptrepo (`standup/wishes/`, `standup/po.tasks.md`
// usw.) — ohne Polling muss der PO das Overlay zu+auf machen für frische Daten.
// 5s ist genug Schonung gegenüber der Disk; in Demo-/Detail-View NICHT
// nachladen (sonst würde sich der `current`-Markdown-Block neu rendern und
// scrollPosition/Lesefluss kaputt machen).
let overlayTimer: ReturnType<typeof setInterval> | undefined
onMounted(() => {
  load()
  overlayTimer = setInterval(() => { if (!data.value?.current) load() }, 5000)
})
onBeforeUnmount(() => { if (overlayTimer) clearInterval(overlayTimer) })
watch(() => props.kind, () => load())
</script>

<template>
  <section class="overlay">
    <div class="ov-bar">
      <button v-if="data?.current" class="ghost" @click="load()">← Liste</button>
      <span v-else class="ov-title"><Icon :name="TITLE_ICON[kind]" class="ic" /> {{ TITLES[kind] }}</span>

      <!-- Wunsch-Filter nur in der Liste, nicht im Detail -->
      <div v-if="kind === 'wishes' && !data?.current" class="ov-filter">
        <button class="chip" :class="{ active: wishFilter==='open' }" @click="wishFilter='open'">Offen</button>
        <button class="chip" :class="{ active: wishFilter==='all' }" @click="wishFilter='all'">Alle</button>
        <button class="chip" :class="{ active: wishFilter==='done' }" @click="wishFilter='done'">Erledigt</button>
      </div>

      <!-- Q&A-Filter: Offen (Default) | Archiv | Alle -->
      <div v-if="kind === 'qa'" class="ov-filter">
        <button class="chip" :class="{ active: qaFilter==='open' }"    @click="qaFilter='open'">Offen</button>
        <button class="chip" :class="{ active: qaFilter==='archive' }" @click="qaFilter='archive'">Archiv</button>
        <button class="chip" :class="{ active: qaFilter==='all' }"     @click="qaFilter='all'">Alle</button>
      </div>

      <!-- Tasks-Filter: Offen (Default) | Done | Alle -->
      <div v-if="kind === 'tasks'" class="ov-filter">
        <button class="chip" :class="{ active: taskFilter==='open' }" @click="taskFilter='open'">Offen</button>
        <button class="chip" :class="{ active: taskFilter==='done' }" @click="taskFilter='done'">Done</button>
        <button class="chip" :class="{ active: taskFilter==='all' }"  @click="taskFilter='all'">Alle</button>
      </div>

      <!-- Feedback-Filter: Klasse + Author (nur in der Liste). -->
      <div v-if="kind === 'feedback' && !data?.current" class="ov-filter">
        <button class="chip" :class="{ active: fbFilter==='all' }"    @click="fbFilter='all'">Alle</button>
        <button class="chip" :class="{ active: fbFilter==='rounds' }" @click="fbFilter='rounds'" title="Nur Sprint-Runden">Sprint</button>
        <button class="chip" :class="{ active: fbFilter==='other' }"  @click="fbFilter='other'" title="Quality-Checks, Live-Bugs, Audits …">Reports</button>
        <select v-if="fbAuthors.length" v-model="fbAuthor" class="chip-select" title="Nach Author filtern">
          <option value="">alle Authors</option>
          <option v-for="n in fbAuthors" :key="n" :value="n">{{ n }}</option>
        </select>
      </div>

    </div>

    <!-- LISTE (Reports/Feedback/Wishes — Q&A + Tasks haben eigene Karten-Layouts) -->
    <ul v-if="!data?.current && kind !== 'qa' && kind !== 'tasks'" class="ov-list">
      <!-- Reports -->
      <template v-if="kind === 'reports'">
        <li v-for="r in items" :key="r.file" @click="load(r.file)">
          <span class="r-date">{{ r.date }}</span>
          <span class="r-mid">{{ r.sprint || r.preview || '—' }}</span>
          <span class="r-end">{{ r.duration || '' }}</span>
        </li>
      </template>
      <!-- Feedback -->
      <template v-else-if="kind === 'feedback'">
        <li v-for="r in items" :key="r.file" @click="load(r.file)">
          <span class="r-date">{{ r.date }}</span>
          <span class="fb-type" :style="{ color: typeColor(r.type), borderColor: typeColor(r.type)+'66', background: typeColor(r.type)+'14' }">{{ typeLabel(r.type) }}</span>
          <span v-if="r.author" class="fb-author">@{{ r.author }}</span>
          <span class="r-mid">{{ r.preview || '—' }}</span>
          <span v-if="r.kind === 'round'" class="r-end">{{ r.agents }} 🗣</span>
        </li>
      </template>
      <!-- Wünsche -->
      <template v-else>
        <li v-for="w in items" :key="w.file" @click="load(w.file)" class="w-row">
          <span class="pill" :style="{ background: STATUS_COLOR[w.status]+'22', color: STATUS_COLOR[w.status], borderColor: STATUS_COLOR[w.status]+'66' }">{{ STATUS_LABEL[w.status] || w.status }}</span>
          <span class="prio" :style="{ color: PRIO_COLOR[w.priority] }">●</span>
          <span class="w-title">{{ w.title }}</span>
          <span class="w-who" :title="w.authorRole && w.targetRole ? `${w.authorRole} → ${w.targetRole}` : (w.authorRole || w.targetRole || '')"><b>{{ w.author }}</b> → {{ w.target }}</span>
        </li>
      </template>
      <li v-if="!items.length" class="muted nolink">{{ EMPTY[kind] }}</li>
    </ul>

    <!-- Tasks: Titel-Karten, Click expandiert Body inline (Markdown→HTML
         vom Server). Done-Tasks sind dimmed (analog Q&A-Archiv). -->
    <div v-if="kind === 'tasks'" class="task-list">
      <article v-for="t in items" :key="t.id" class="task-card" :class="{ done: t.done, expanded: expandedTasks.has(t.id) }" :ref="(el) => { if (el) taskCardRefs[t.id] = el as HTMLElement }">
        <header class="task-head" role="button" @click="toggleTask(t.id)">
          <span class="task-toggle"><Icon :name="expandedTasks.has(t.id) ? 'mdi:chevron-down' : 'mdi:chevron-right'" /></span>
          <span class="task-state">{{ t.done ? '✓' : '○' }}</span>
          <h3 class="task-title">{{ t.title }}</h3>
          <span v-if="t.author" class="task-author" :title="t.authorRole">@{{ t.author }}</span>
        </header>
        <!-- Body kommt fertig vom Server (render() — Listen, Tabellen, Code-Blöcke). -->
        <div v-if="expandedTasks.has(t.id)" class="task-body md" v-html="t.html"></div>
      </article>
      <div v-if="!items.length" class="task-empty">{{ EMPTY['tasks'] }}</div>
    </div>

    <!-- Q&A: collapsible Karten (Frage sichtbar, Antwort/Details auf Klick).
         Die Anleitungs-/Info-Seite des PO — scanbar, kein "PO fragt"-Header. -->
    <div v-if="kind === 'qa'" class="qa-list">
      <article v-for="q in items" :key="q.file" class="qa-card" :class="{ dismissed: q.dismissed, open: qaOpen.has(q.file) }">
        <header class="qa-head" role="button" @click="toggleQa(q.file)">
          <Icon :name="qaOpen.has(q.file) ? 'mdi:chevron-down' : 'mdi:chevron-right'" class="qa-caret" />
          <h3 class="qa-q">{{ q.question }}</h3>
          <time class="qa-time" :title="`erstellt: ${q.created} · beantwortet: ${q.answered}`">{{ q.created }}</time>
        </header>
        <div v-if="qaOpen.has(q.file)" class="qa-detail">
          <div class="qa-answer-head"><b>Antwort von {{ q.answered_by }}:</b></div>
          <!-- Antwort-HTML kommt fertig vom Server (md.render in qa.get.ts). -->
          <div class="md qa-a" v-html="q.html"></div>
          <div class="qa-actions">
            <button v-if="!q.dismissed" class="qa-mini" @click.stop="qaDismissConfirm(q.file)" title="Diese Karte ausblenden (bleibt im Archiv)"><Icon name="mdi:close" class="ic" /> ausblenden</button>
            <button v-else class="qa-mini" @click.stop="qaDismiss(q.file, false)" title="Wieder in die offene Liste holen"><Icon name="mdi:restore" class="ic" /> wieder einblenden</button>
            <span v-if="q.dismissed && q.dismissed_at" class="qa-dismissed-at">ausgeblendet {{ q.dismissed_at }}</span>
          </div>
        </div>
      </article>
      <div v-if="!items.length" class="qa-empty">{{ EMPTY['qa'] }}</div>
    </div>

    <!-- Submit-Form (nur ✨ Wünsche, nur in der Liste) -->
    <div v-if="kind === 'wishes' && !data?.current" class="wish-form">
      <button v-if="!formOpen" class="ghost wish-form-toggle" @click="formOpen = true">+ Neuen Wunsch einreichen</button>
      <form v-else @submit.prevent="submitWish">
        <div class="wf-row">
          <label>Von <select v-model="fAuthor"><option v-for="n in TEAM" :key="n">{{ n }}</option></select></label>
          <label>An <select v-model="fTarget"><option value="team">team (alle)</option><option v-for="n in TEAM" :key="n">{{ n }}</option></select></label>
          <label>Prio
            <select v-model="fPrio">
              <option value="low">low</option><option value="med">med</option><option value="high">high</option>
            </select>
          </label>
        </div>
        <input v-model="fTitle" class="wf-title" placeholder="Wunsch-Titel (z. B. Sort-Toggle für Team-Grid)" maxlength="120" required />
        <textarea v-model="fBody" class="wf-body" placeholder="Was & Warum & ggf. wie umsetzbar (Markdown ok)" rows="4" maxlength="5000"></textarea>
        <div class="wf-actions">
          <button type="button" class="ghost" @click="formOpen = false">Abbrechen</button>
          <button type="submit" class="ghost primary" :disabled="fBusy || !fTitle.trim()">{{ fBusy ? '…' : 'Wunsch einreichen' }}</button>
        </div>
      </form>
    </div>

    <!-- DETAIL -->
    <div v-else class="ov-detail">
      <!-- Feedback: Gruppierungs-Toggle (nur bei Sprint-Runden, sonst kein
           (a)/(b)/(c)-Schema; sonstige Reports = direkter Markdown-Render). -->
      <div v-if="kind === 'feedback' && data?.current?.kind === 'round'" class="fb-actions">
        <button class="chip" :class="{ active: fbGroup==='agent' }"    @click="fbGroup='agent'"    title="Sektionen pro Agent"><Icon name="mdi:account-voice" class="ic" /> nach Agent</button>
        <button class="chip" :class="{ active: fbGroup==='question' }" @click="fbGroup='question'" title="Alle Antworten pro Frage zusammen"><Icon name="mdi:chart-box-outline" class="ic" /> nach Frage</button>
      </div>

      <!-- Author/Type-Header bei sonstigen Reports (Quality-Check etc.). -->
      <div v-if="kind === 'feedback' && data?.current?.kind === 'other'" class="fb-other-head">
        <span class="fb-type" :style="{ color: typeColor(data.current.type), borderColor: typeColor(data.current.type)+'66', background: typeColor(data.current.type)+'14' }">{{ typeLabel(data.current.type) }}</span>
        <span v-if="data.current.author" class="fb-author">@{{ data.current.author }}</span>
        <span class="r-date">{{ data.current.date }}</span>
      </div>

      <!-- Feedback nach Frage: aus data.current.byQuestion (nur Sprint-Runden) -->
      <div v-if="kind === 'feedback' && data?.current?.kind === 'round' && fbGroup === 'question'" class="md fb-by-q">
        <template v-for="q in ['(a)', '(b)', '(c)']" :key="q">
          <h2>{{ q }}</h2>
          <div v-for="entry in (data?.current?.byQuestion?.[q] || [])" :key="q + entry.agent" class="fb-ans">
            <div class="fb-ans-head"><b>@{{ entry.agent }}</b><span v-if="entry.role" class="role-tag"> · {{ entry.role }}</span></div>
            <!-- Server liefert volles MD→HTML (inkl. Listen, Tabellen, Code-Blöcken). -->
            <div class="fb-ans-body md" v-html="entry.html || inline(entry.answer)"></div>
          </div>
          <div v-if="!(data?.current?.byQuestion?.[q] || []).length" class="muted">— keine Antworten —</div>
        </template>
      </div>

      <!-- Wünsche: Status-Toggle in der Detail-Ansicht -->
      <div v-if="kind === 'wishes'" class="w-actions">
        <span class="pill" :style="{ background: STATUS_COLOR[data?.current?.status]+'22', color: STATUS_COLOR[data?.current?.status], borderColor: STATUS_COLOR[data?.current?.status]+'66' }">{{ STATUS_LABEL[data?.current?.status] || data?.current?.status }}</span>
        <span class="prio-tag" :style="{ color: PRIO_COLOR[data?.current?.priority] }">priority: {{ data?.current?.priority }}</span>
        <span class="w-who">
          <b>{{ data?.current?.author }}</b><span v-if="data?.current?.authorRole" class="role-tag"> · {{ data?.current?.authorRole }}</span>
          → <b>{{ data?.current?.target }}</b><span v-if="data?.current?.targetRole" class="role-tag"> · {{ data?.current?.targetRole }}</span>
          · {{ data?.current?.created }}
        </span>
        <button class="ghost" @click="data?.current && toggleStatus(data.current.file)">Status weiterschalten →</button>
      </div>
      <!-- HTML-Render: immer, AUSSER bei Feedback-Sprint-Runden im Frage-Modus. -->
      <div v-if="!(kind === 'feedback' && data?.current?.kind === 'round' && fbGroup === 'question')" class="md" v-html="data?.current?.html"></div>
    </div>
  </section>
</template>

<style scoped>
.overlay { background: #161b22; border: 1px solid #21262d; border-radius: 10px; padding: 6px 18px 18px; margin: 16px 0 22px; }
.ov-bar { display: flex; align-items: center; justify-content: space-between; gap: 8px; padding: 8px 0; position: sticky; top: 0; background: #161b22; z-index: 1; flex-wrap: wrap; }
.ov-title { color: #e6edf3; font-size: 14px; }
.ov-filter { display: inline-flex; gap: 4px; }
.chip { background: #0d1117; color: #8b949e; border: 1px solid #30363d; border-radius: 999px; padding: 3px 10px; font: inherit; font-size: 12px; cursor: pointer; }
.chip:hover { border-color: #58a6ff; color: #c9d1d9; }
.chip.active { border-color: #58a6ff; color: #58a6ff; background: #161f2e; }
.ghost { background: #161b22; color: #c9d1d9; border: 1px solid #30363d; border-radius: 6px; padding: 5px 12px; font: inherit; cursor: pointer; }
.ghost:hover { border-color: #58a6ff; color: #e6edf3; }

.ov-list { list-style: none; margin: 0; padding: 4px 0; display: flex; flex-direction: column; gap: 6px; }
.ov-list li { display: flex; align-items: baseline; gap: 12px; padding: 9px 11px; border: 1px solid #21262d; border-radius: 8px; cursor: pointer; flex-wrap: wrap; }
.ov-list li:hover { border-color: #58a6ff; background: #0d1117; }
.ov-list li.nolink { cursor: default; border: 0; }
.r-date { flex: 0 0 96px; color: #58a6ff; font-weight: 700; }
.r-mid  { flex: 1; min-width: 0; color: #e6edf3; }
.r-end  { flex: 0 0 auto; color: #8b949e; font-size: 12px; }

.w-row { gap: 8px 12px; }
.w-title { flex: 1; min-width: 0; color: #e6edf3; }
.w-who   { color: #8b949e; font-size: 12px; min-width: 0; overflow-wrap: anywhere; }
.w-who b { color: #c9d1d9; }
.w-actions .w-who { flex: 1 1 100%; }     /* im Detail: eigene Zeile, darf umbrechen */
.pill    { flex: 0 0 auto; font-size: 11px; font-weight: 700; border: 1px solid; border-radius: 999px; padding: 2px 8px; }
.prio    { flex: 0 0 auto; font-size: 18px; line-height: 1; }
.prio-tag{ font-size: 12px; }

.w-actions { display: flex; align-items: center; gap: 12px; flex-wrap: wrap; margin: 8px 0 12px; padding-bottom: 10px; border-bottom: 1px solid #21262d; }
.role-tag { color: #6e7681; font-weight: 400; font-size: 12px; }

/* Wish-Submit-Form */
.wish-form { margin-top: 14px; padding-top: 12px; border-top: 1px dashed #21262d; }
.wish-form-toggle { width: 100%; }
.wish-form form { display: flex; flex-direction: column; gap: 8px; }
.wf-row { display: flex; gap: 10px; flex-wrap: wrap; font-size: 12px; color: #8b949e; }
.wf-row label { display: inline-flex; align-items: center; gap: 6px; }
.wf-row select { background: #0d1117; color: #c9d1d9; border: 1px solid #30363d; border-radius: 6px; padding: 4px 6px; font: inherit; }
.wf-title, .wf-body { background: #0d1117; color: #c9d1d9; border: 1px solid #30363d; border-radius: 6px; padding: 7px 10px; font: inherit; }
.wf-body { font-family: inherit; resize: vertical; min-height: 80px; }
.wf-actions { display: flex; justify-content: flex-end; gap: 8px; }
.ghost.primary { color: #fff; background: #238636; border-color: #238636; }
.ghost.primary:hover { background: #2ea043; border-color: #2ea043; }
.ghost:disabled { opacity: .5; cursor: not-allowed; }

/* Q&A — collapsible Karten. Frage = klickbare Kopfzeile, Antwort eingeklappt
   (PO: Anleitungs-/Info-Seite, scanbar). Kein inner-scroll mehr (Page-Flow). */
.qa-list { display: flex; flex-direction: column; gap: 10px; padding: 6px 0 4px; }
.qa-card { border: 1px solid #21262d; border-radius: 10px; background: #0d1117; overflow: hidden; }
.qa-card.open { border-color: #58a6ff; }
.qa-card.dismissed { opacity: .55; border-style: dashed; }
.qa-head { display: flex; align-items: baseline; gap: 10px; padding: 11px 14px; cursor: pointer; user-select: none; }
.qa-head:hover { background: #161b22; }
.qa-caret { flex: 0 0 auto; color: #58a6ff; font-size: 15px; align-self: center; }
.qa-q { flex: 1; min-width: 0; font-size: 15px; color: #e6edf3; margin: 0; line-height: 1.35; font-weight: 600; }
.qa-time { flex: 0 0 auto; color: #6e7681; font-size: 11px; font-family: ui-monospace, SFMono-Regular, Menlo, monospace; }
.qa-detail { padding: 2px 14px 12px; border-top: 1px dashed #21262d; }
.qa-answer-head { font-size: 12px; color: #8b949e; margin: 8px 0 4px; }
.qa-answer-head b { color: #3fb950; }
.qa-a { color: #c9d1d9; font-size: 13px; }
.qa-a :deep(p) { margin: 4px 0; }
.qa-a :deep(ul), .qa-a :deep(ol) { margin: 4px 0; }
.qa-actions { display: flex; align-items: center; gap: 10px; margin-top: 12px; }
/* "ausblenden" bewusst dezent (klein, grau) — Bestätigung passiert im Handler. */
.qa-mini { background: transparent; border: 0; color: #6e7681; font: inherit; font-size: 11px; cursor: pointer; display: inline-flex; align-items: center; gap: 4px; padding: 2px 5px; border-radius: 5px; }
.qa-mini:hover { color: #f85149; background: #2d141633; }
.qa-dismissed-at { font-size: 11px; color: #6e7681; }
.qa-empty { padding: 18px; text-align: center; color: #6e7681; font-size: 13px; border: 1px dashed #21262d; border-radius: 8px; }

/* Tasks — Titel-Karten mit Click-Expand (PO-Wunsch: Details sichtbar
   per Click statt nur Title). Done-Tasks bleiben drin, aber dimmed. */
/* task-list: max-height vom Container REMOVED (PO 02:35 "wenn ich eine
   Briefing box auf mache, werden die anderen gequetscht"). Vorher 70vh +
   overflow:auto auf dem Container — wenn ein Item aufgeklappt war + Body
   gross, fuellte es den View und die anderen Cards verschwanden in den
   Scroll-Bereich (gefuehlt: gequetscht). Stattdessen scrollt jetzt das
   Overlay als Ganzes (ov-bar bleibt sticky), und LANGE Bodies bekommen
   eine eigene innere max-height mit overflow. */
.task-list { display: flex; flex-direction: column; gap: 8px; padding: 6px 0 4px; }
.task-card { border: 1px solid #21262d; border-radius: 10px; background: #0d1117; overflow: hidden; scroll-margin-top: 64px; }
.task-card.expanded { border-color: #58a6ff; box-shadow: 0 0 0 1px #58a6ff22; }
.task-card.done { opacity: .55; border-style: dashed; }
.task-head { display: flex; align-items: baseline; gap: 10px; padding: 10px 14px; cursor: pointer; user-select: none; }
.task-head:hover { background: #161b22; }
.task-toggle { flex: 0 0 auto; color: #58a6ff; font-size: 14px; width: 14px; }
.task-state { flex: 0 0 auto; color: #3fb950; font-size: 14px; width: 14px; }
.task-card.done .task-state { color: #3fb950; }
.task-card:not(.done) .task-state { color: #6e7681; }
.task-title { flex: 1; min-width: 0; font-size: 15px; color: #e6edf3; margin: 0; line-height: 1.35; font-weight: 600; }
.task-card.done .task-title { text-decoration: line-through; color: #8b949e; }
.task-author { flex: 0 0 auto; font-size: 11px; font-weight: 700; color: #58a6ff; background: #161f2e; border: 1px solid #1f6feb44; border-radius: 5px; padding: 1px 7px; }
/* Body hat eine eigene max-height (60vh) damit sehr lange Tasks (z.B.
   PO-Entscheidungen mit 20+ Bullets) nicht den ganzen Viewport fluten —
   stattdessen scrollt der Body innerhalb der Card. Nicht-expandierte Cards
   bleiben kompakt darueber und darunter sichtbar. */
.task-body { padding: 4px 14px 14px; border-top: 1px dashed #21262d; }
.task-empty { padding: 18px; text-align: center; color: #6e7681; font-size: 13px; border: 1px dashed #21262d; border-radius: 8px; }

/* Feedback-Liste: Type-Badge + Author-Tag (zusätzlich zu r-date/r-mid/r-end). */
.fb-type { flex: 0 0 auto; font-size: 11px; font-weight: 600; border: 1px solid; border-radius: 999px; padding: 2px 9px; letter-spacing: .02em; text-transform: lowercase; }
.fb-author { flex: 0 0 auto; font-size: 12px; font-weight: 700; color: #58a6ff; background: #161f2e; border: 1px solid #1f6feb44; border-radius: 5px; padding: 1px 7px; }
.chip-select { background: #0d1117; color: #c9d1d9; border: 1px solid #30363d; border-radius: 999px; padding: 3px 10px; font: inherit; font-size: 12px; cursor: pointer; }
.chip-select:hover { border-color: #58a6ff; }
.fb-other-head { display: flex; align-items: center; gap: 10px; margin: 4px 0 12px; padding-bottom: 8px; border-bottom: 1px solid #21262d; flex-wrap: wrap; }

/* Feedback-Aggregation */
.fb-actions { display: flex; gap: 6px; margin: 4px 0 12px; flex-wrap: wrap; }
.fb-by-q h2 { font-size: 16px; border-bottom: 1px solid #21262d; padding-bottom: 4px; margin: 18px 0 10px; color: #d29922; }
.fb-ans { padding: 8px 10px; border: 1px solid #21262d; border-radius: 8px; margin-bottom: 6px; }
.fb-ans-head { font-size: 12px; color: #c9d1d9; margin-bottom: 4px; }
.fb-ans-body { font-size: 13px; color: #c9d1d9; }
.fb-ans-body :deep(code) { background: #0d1117; border: 1px solid #21262d; border-radius: 4px; padding: 1px 5px; font-size: 12px; }

:deep(.md h1) { font-size: 20px; }
:deep(.md h2) { font-size: 16px; border-bottom: 1px solid #21262d; padding-bottom: 4px; margin-top: 22px; }
:deep(.md h3) { font-size: 14px; }
:deep(.md h1), :deep(.md h2), :deep(.md h3) { color: #e6edf3; }
:deep(.md p), :deep(.md li) { font-size: 13px; }
/* Inline-`code`-Pille — NICHT der <code> in einem Fenced-Block (.codeblock). */
:deep(.md :not(.codeblock) > code), :deep(.md p code), :deep(.md li code) { background: #0d1117; border: 1px solid #21262d; border-radius: 4px; padding: 1px 5px; font-size: 12px; }
/* Fenced Code Block (```…```) im GitHub-Dark-Look. */
:deep(.md .codeblock) { background: #161b22; border: 1px solid #30363d; border-radius: 6px; padding: 10px 12px; margin: 10px 0; overflow-x: auto; font-size: 12px; line-height: 1.5; }
:deep(.md .codeblock code) { display: block; background: none; border: 0; padding: 0; font-family: ui-monospace, SFMono-Regular, Menlo, monospace; color: #c9d1d9; white-space: pre; }
/* Syntax-Token-Farben (GitHub-Dark) — vom Mini-Highlighter in md.ts gesetzt. */
:deep(.codeblock .hl-comment) { color: #8b949e; font-style: italic; }
:deep(.codeblock .hl-string)  { color: #a5d6ff; }
:deep(.codeblock .hl-keyword) { color: #ff7b72; }
:deep(.codeblock .hl-builtin) { color: #d2a8ff; }
:deep(.codeblock .hl-flag)    { color: #79c0ff; }
:deep(.codeblock .hl-var)     { color: #ffa657; }
:deep(.codeblock .hl-num)     { color: #79c0ff; }
:deep(.codeblock .hl-key)     { color: #7ee787; }
:deep(.codeblock .hl-symbol)  { color: #ffa657; }
:deep(.md hr) { border: 0; border-top: 1px solid #21262d; margin: 16px 0; }
:deep(.md table) { border-collapse: collapse; width: 100%; margin: 10px 0; font-size: 13px; }
:deep(.md th), :deep(.md td) { border: 1px solid #21262d; padding: 5px 9px; text-align: left; vertical-align: top; }
:deep(.md th) { background: #0d1117; color: #e6edf3; }
:deep(.md ul), :deep(.md ol) { padding-left: 20px; }

@media (max-width: 640px) {
  .overlay { padding: 6px 12px 14px; }
  :deep(.md table) { display: block; overflow-x: auto; }

  /* Mobil kompakter (PO 2026-06-01): Listen enger, Datum klein, Text full-width
     + Umbruch (Feedback-Preview lief vorher rechts aus der Karte). */
  .ov-list { gap: 6px; }
  .ov-list li { padding: 8px 10px; gap: 3px 8px; }
  .r-date { flex: 0 0 auto; font-size: 12px; }
  .r-mid  { flex: 1 1 100%; min-width: 0; overflow-wrap: anywhere; }
  .r-end  { flex: 0 0 auto; }
  .fb-type, .fb-author { font-size: 10px; }

  /* Docs/Q&A kompakter: Datum egal (ausgeblendet), kleinere Frage, weniger Padding. */
  .qa-list { gap: 8px; }
  .qa-head { padding: 9px 12px; gap: 8px; }
  .qa-q { font-size: 14px; }
  .qa-time { display: none; }
  .qa-caret { font-size: 14px; }
  .qa-detail { padding: 2px 12px 10px; }

  /* Briefing/Tasks-Karten kompakter. */
  .task-head { padding: 9px 12px; }
  .task-title { font-size: 14px; }
}
</style>
