<script setup lang="ts">
// /approvals — Freigabe-Queue. Bobs stellen Anträge (Production-Deploy, Merge nach
// master, externe Kommunikation …), Austin entscheidet approve/reject. Karten mit
// Click-Expand für den Body; Antrags-Form im Footer. Quelle: /api/approvals.
useHead({ title: 'Approvals · Stand-up' })

// Tenant-aware (#13): aktiver ?project muss an ALLE Calls (GET liste/detail UND
// POST decide/add), sonst fällt der Server auf das Launcher-Projekt zurück und
// das Panel zeigt/schreibt fremde Tenants. useFetch-key projekt-abhängig, sonst
// Cache-Bleed (der GET 'approvals' war projekt-unabhängig gecacht).
const project = useActiveProject()
const projectQuery = useProjectQuery()   // reaktiv für die useFetch-GET
const projectParam = () => projectQuery.value   // {} oder { project } für $fetch
const { data, refresh } = await useFetch('/api/approvals', {
  key: () => `approvals-${project.value || 'env'}`,
  query: projectQuery,
})

type Filter = 'pending' | 'all' | 'decided'
const filter = ref<Filter>('pending')
const items = computed<any[]>(() => {
  const all = ((data.value as any)?.approvals || []) as any[]
  if (filter.value === 'all') return all
  if (filter.value === 'decided') return all.filter(a => a.status !== 'pending')
  return all.filter(a => a.status === 'pending')
})
const pendingCount = computed(() => ((data.value as any)?.approvals || []).filter((a: any) => a.status === 'pending').length)

const STATUS_COLOR: Record<string, string> = { pending: '#d29922', approved: '#3fb950', rejected: '#f85149' }
const STATUS_LABEL: Record<string, string> = { pending: 'offen', approved: 'freigegeben', rejected: 'abgelehnt' }
const KIND_LABEL: Record<string, string> = { deploy: 'Deploy', merge: 'Merge', other: 'Sonstiges' }
const KIND_ICON: Record<string, string> = { deploy: 'mdi:rocket-launch', merge: 'mdi:source-merge', other: 'mdi:clipboard-text' }

// Body lazy laden + cachen (Liste liefert nur Meta; Detail-HTML kommt per ?file).
const expanded = ref<Set<string>>(new Set())
const bodies = reactive<Record<string, string>>({})
async function toggle(file: string) {
  const s = new Set(expanded.value)
  if (s.has(file)) { s.delete(file); expanded.value = s; return }
  s.add(file); expanded.value = s
  if (bodies[file] === undefined) {
    const res = await $fetch('/api/approvals', { params: { file, ...projectParam() }, cache: 'no-store' }) as any
    bodies[file] = res?.current?.html || '<p class="muted">— kein Detailtext —</p>'
  }
}

async function decide(file: string, decision: 'approved' | 'rejected') {
  await $fetch('/api/approvals', { method: 'POST', query: projectParam(), body: { action: 'decide', file, decision } })
  delete bodies[file]            // Body neu laden falls offen (decided-Stempel etc.)
  await refresh()
}

// Antrags-Form (Footer) — analog Wünsche-Submit.
const TEAM = ['Bob', 'Bill', 'Luke', 'Linus', 'Riker', 'Marvin', 'Dexter', 'Bender', 'Garfield', 'Homer', 'Bridget', 'Mario']
const formOpen = ref(false)
const fReq = ref('Bob')
const fKind = ref<'deploy' | 'merge' | 'other'>('deploy')
const fTitle = ref('')
const fBody = ref('')
const fBusy = ref(false)
async function submitRequest() {
  if (!fTitle.value.trim() || fBusy.value) return
  fBusy.value = true
  try {
    await $fetch('/api/approvals', { method: 'POST', query: projectParam(), body: { action: 'add', requested_by: fReq.value, kind: fKind.value, title: fTitle.value.trim(), body: fBody.value.trim() } })
    fTitle.value = ''; fBody.value = ''; formOpen.value = false
    await refresh()
  } finally { fBusy.value = false }
}

// Eigenes 10s-Polling (approvals hängt nicht am zentralen Layout-Poll).
let timer: ReturnType<typeof setInterval> | undefined
onMounted(() => { timer = setInterval(() => refresh(), 10000) })
onBeforeUnmount(() => { if (timer) clearInterval(timer) })
</script>

<template>
  <div>
    <div class="page-head">
      <h2><Icon name="mdi:check-decagram-outline" class="ic" /> Approvals · Freigaben</h2>
      <span class="ph-sub">Bobs beantragen · Austin entscheidet<span v-if="pendingCount"> · {{ pendingCount }} offen</span></span>
    </div>

    <div class="ov-filter">
      <button class="chip" :class="{ active: filter==='pending' }" @click="filter='pending'">Offen</button>
      <button class="chip" :class="{ active: filter==='all' }"     @click="filter='all'">Alle</button>
      <button class="chip" :class="{ active: filter==='decided' }" @click="filter='decided'">Entschieden</button>
    </div>

    <div class="ap-list">
      <article v-for="a in items" :key="a.file" class="ap-card" :class="a.status">
        <header class="ap-head" role="button" @click="toggle(a.file)">
          <span class="ap-toggle"><Icon :name="expanded.has(a.file) ? 'mdi:chevron-down' : 'mdi:chevron-right'" /></span>
          <span class="pill" :style="{ background: STATUS_COLOR[a.status]+'22', color: STATUS_COLOR[a.status], borderColor: STATUS_COLOR[a.status]+'66' }">{{ STATUS_LABEL[a.status] || a.status }}</span>
          <span class="ap-kind"><Icon :name="KIND_ICON[a.kind] || 'mdi:clipboard-text'" class="ic" /> {{ KIND_LABEL[a.kind] || a.kind }}</span>
          <h3 class="ap-title">{{ a.title }}</h3>
          <span class="ap-who" :title="a.requestedByRole"><b>{{ a.requested_by }}</b></span>
          <span class="ap-date">{{ a.created }}</span>
        </header>

        <div v-if="expanded.has(a.file)" class="ap-body md" v-html="bodies[a.file] || '<p>…</p>'"></div>

        <div class="ap-actions">
          <button class="ap-btn approve" :class="{ on: a.status==='approved' }" @click="decide(a.file, 'approved')" title="Freigeben"><Icon name="mdi:check" class="ic" /> approve</button>
          <button class="ap-btn reject" :class="{ on: a.status==='rejected' }" @click="decide(a.file, 'rejected')" title="Ablehnen"><Icon name="mdi:close" class="ic" /> reject</button>
          <span v-if="a.decided" class="ap-decided">entschieden {{ a.decided }}</span>
        </div>
      </article>
      <div v-if="!items.length" class="ap-empty">— keine {{ filter==='pending' ? 'offenen ' : '' }}Freigaben —</div>
    </div>

    <!-- Antrag stellen (Footer) -->
    <div class="ap-form">
      <button v-if="!formOpen" class="ghost ap-form-toggle" @click="formOpen = true"><Icon name="mdi:plus" class="ic" /> Freigabe beantragen</button>
      <form v-else @submit.prevent="submitRequest">
        <div class="apf-row">
          <label>Von <select v-model="fReq"><option v-for="n in TEAM" :key="n">{{ n }}</option></select></label>
          <label>Art
            <select v-model="fKind"><option value="deploy">Deploy</option><option value="merge">Merge</option><option value="other">Sonstiges</option></select>
          </label>
        </div>
        <input v-model="fTitle" class="apf-title" placeholder="Freigabe-Titel (z. B. Staging→Production Deploy acme_website)" maxlength="120" required />
        <textarea v-model="fBody" class="apf-body" placeholder="Was & Warum jetzt & was hängt dran (Markdown ok)" rows="4" maxlength="5000"></textarea>
        <div class="apf-actions">
          <button type="button" class="ghost" @click="formOpen = false">Abbrechen</button>
          <button type="submit" class="ghost primary" :disabled="fBusy || !fTitle.trim()">{{ fBusy ? '…' : 'Antrag stellen' }}</button>
        </div>
      </form>
    </div>
  </div>
</template>

<style scoped>
.ov-filter { display: inline-flex; gap: 4px; margin: 8px 0 12px; }
.ap-list { display: flex; flex-direction: column; gap: 10px; }
.ap-card { border: 1px solid #21262d; border-radius: 10px; background: #0d1117; overflow: hidden; }
.ap-card.pending { border-left: 3px solid #d29922; }
.ap-card.approved { border-left: 3px solid #3fb950; opacity: .85; }
.ap-card.rejected { border-left: 3px solid #f85149; opacity: .7; }
.ap-head { display: flex; align-items: baseline; gap: 10px; padding: 10px 14px; cursor: pointer; user-select: none; flex-wrap: wrap; }
.ap-head:hover { background: #161b22; }
.ap-toggle { flex: 0 0 auto; color: #58a6ff; font-size: 14px; width: 12px; }
.pill { flex: 0 0 auto; font-size: 11px; font-weight: 700; border: 1px solid; border-radius: 999px; padding: 2px 8px; }
.ap-kind { flex: 0 0 auto; font-size: 12px; color: #8b949e; }
.ap-title { flex: 1; min-width: 0; font-size: 15px; color: #e6edf3; margin: 0; line-height: 1.35; font-weight: 600; }
.ap-who { flex: 0 0 auto; font-size: 12px; color: #8b949e; }
.ap-who b { color: #58a6ff; }
.ap-date { flex: 0 0 auto; font-size: 12px; color: #6e7681; font-family: ui-monospace, SFMono-Regular, Menlo, monospace; }
.ap-body { padding: 4px 14px 12px; border-top: 1px dashed #21262d; }
.ap-actions { display: flex; align-items: center; gap: 10px; padding: 8px 14px; border-top: 1px solid #161b22; }
.ap-btn { background: transparent; border: 1px solid #30363d; border-radius: 6px; padding: 4px 12px; font: inherit; font-size: 12px; cursor: pointer; }
.ap-btn.approve { color: #3fb950; }
.ap-btn.approve:hover, .ap-btn.approve.on { border-color: #238636; background: #102310; }
.ap-btn.reject { color: #f85149; }
.ap-btn.reject:hover, .ap-btn.reject.on { border-color: #f85149; background: #2d1416; }
.ap-decided { font-size: 11px; color: #6e7681; margin-left: auto; }
.ap-empty { padding: 18px; text-align: center; color: #6e7681; font-size: 13px; border: 1px dashed #21262d; border-radius: 8px; }

.ap-form { margin-top: 16px; padding-top: 12px; border-top: 1px dashed #21262d; }
.ap-form-toggle { width: 100%; }
.ap-form form { display: flex; flex-direction: column; gap: 8px; }
.apf-row { display: flex; gap: 10px; flex-wrap: wrap; font-size: 12px; color: #8b949e; }
.apf-row label { display: inline-flex; align-items: center; gap: 6px; }
.apf-row select { background: #0d1117; color: #c9d1d9; border: 1px solid #30363d; border-radius: 6px; padding: 4px 6px; font: inherit; }
.apf-title, .apf-body { background: #0d1117; color: #c9d1d9; border: 1px solid #30363d; border-radius: 6px; padding: 7px 10px; font: inherit; }
.apf-body { resize: vertical; min-height: 80px; }
.apf-actions { display: flex; justify-content: flex-end; gap: 8px; }
.ghost.primary { color: #fff; background: #238636; border-color: #238636; }
.ghost.primary:hover { background: #2ea043; border-color: #2ea043; }
.ghost:disabled { opacity: .5; cursor: not-allowed; }

@media (max-width: 640px) {
  .ap-title { flex: 1 1 100%; }
}
</style>
