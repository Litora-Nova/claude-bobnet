<script setup lang="ts">
// Bobiverse-Übersicht (#9 + #10): ALLE registrierten Projekt-Bobiverses gestapelt —
// je Projekt Aktivitäts-Status (registered/running/working/idle, blocked prominent)
// + die letzten Heartbeats (Cross-Projekt-View: man SIEHT, wer parallel arbeitet).
// Tenant-NEUTRAL (Gate-Auflage B): diese Seite zeigt die Flotte, nie nur das
// aktive Projekt. Klick auf ein Projekt = Switch OHNE Neustart (Cookie + reaktive
// Queries in useLive) → zurück zur Team-Seite.
const { data, refresh } = await useProjects()
const active = useActiveProject()
const router = useRouter()

let poll: ReturnType<typeof setInterval> | undefined
onMounted(() => { poll = setInterval(() => refresh(), 5000) })
onBeforeUnmount(() => { if (poll) clearInterval(poll) })

const projects = computed(() => (data.value as any)?.projects || [])

// Anzeige-Semantik der vier Stufen + blocked (Sonderstatus, urgent).
const ACT: Record<string, { label: string; cls: string }> = {
  blocked:    { label: 'blockiert',   cls: 'act-blocked' },
  working:    { label: 'arbeitet',    cls: 'act-working' },
  running:    { label: 'läuft',       cls: 'act-running' },
  idle:       { label: 'idle',        cls: 'act-idle' },
  registered: { label: 'registriert', cls: 'act-registered' },
}
const act = (a: string) => ACT[a] || ACT.registered

function open(p: any) { active.value = p.uid; router.push('/') }   // Switch ohne Neustart
const initial = (p: any) => (p.label || p.name || '?').slice(0, 1).toUpperCase()
</script>

<template>
  <div class="bobiverse">
    <p class="intro"><Icon name="mdi:orbit" class="ic" /> Alle registrierten Bob-Netze — Klick wechselt das Dashboard auf das Team (ohne Neustart).</p>
    <div v-for="p in projects" :key="p.uid" class="planet" :class="act(p.activity).cls" @click="open(p)" role="button" tabindex="0" @keydown.enter="open(p)">
      <div class="planet-head">
        <img v-if="p.icon" :src="p.icon" class="planet-icon" :alt="p.label" />
        <span v-else class="planet-initial">{{ initial(p) }}</span>
        <div class="planet-id">
          <!-- Leerzeichen vor dem Badge: trennt den A11y-Namen ("… Stand-up aktiv" statt "…Stand-upaktiv") -->
          <span class="planet-label">{{ p.title || p.label }} <span v-if="active === p.uid" class="active-tag" title="aktives Projekt">aktiv</span></span>
          <span class="planet-meta">{{ p.uid }} · PO {{ p.po }}<template v-if="p.responsibility"> · {{ p.responsibility }}</template></span>
        </div>
        <span class="act-pill" :class="act(p.activity).cls">{{ act(p.activity).label }}</span>
      </div>
      <ul v-if="p.recentBeats?.length" class="beats">
        <li v-for="(b, i) in p.recentBeats" :key="i" class="beat">
          <span class="beat-ts">{{ b.ts }}</span>
          <span class="beat-agent">{{ b.agent }}</span>
          <span class="beat-dot" :class="`dot-${b.status}`" :title="b.status"></span>
          <span class="beat-msg">{{ b.msg }}</span>
        </li>
      </ul>
      <p v-else class="beats-empty">noch keine Heartbeats</p>
    </div>
    <p v-if="!projects.length" class="beats-empty">Keine Projekte registriert (projects.registry.json fehlt oder ist leer).</p>
  </div>
</template>

<style scoped>
.bobiverse { display: flex; flex-direction: column; gap: 14px; }
.intro { color: #8b949e; margin: 2px 0 4px; display: flex; align-items: center; gap: 6px; }
.planet { border: 1px solid #30363d; border-radius: 10px; background: #0d1117; padding: 12px 14px; cursor: pointer; transition: border-color .15s; }
.planet:hover { border-color: #58a6ff; }
.planet.act-blocked { border-color: #f85149; }
.planet-head { display: flex; align-items: center; gap: 10px; }
.planet-icon { width: 36px; height: 36px; border-radius: 8px; object-fit: cover; }
.planet-initial { width: 36px; height: 36px; border-radius: 8px; background: #21262d; color: #c9d1d9; display: inline-flex; align-items: center; justify-content: center; font-weight: 700; font-size: 17px; }
.planet-id { display: flex; flex-direction: column; min-width: 0; flex: 1; }
.planet-label { color: #e6edf3; font-weight: 600; }
.active-tag { margin-left: 8px; font-size: 11px; color: #3fb950; border: 1px solid #2ea04366; border-radius: 999px; padding: 1px 7px; vertical-align: 1px; }
.planet-meta { color: #8b949e; font-size: 12px; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
.act-pill { font-size: 12px; border-radius: 999px; padding: 2px 10px; border: 1px solid #30363d; color: #8b949e; flex-shrink: 0; }
.act-pill.act-working { color: #3fb950; border-color: #2ea04366; }
.act-pill.act-running { color: #58a6ff; border-color: #1f6feb66; }
.act-pill.act-blocked { color: #f85149; border-color: #f8514966; font-weight: 700; }
.act-pill.act-idle { color: #8b949e; }
.act-pill.act-registered { color: #6e7681; border-style: dashed; }
.beats { list-style: none; margin: 10px 0 0; padding: 8px 0 0; border-top: 1px solid #21262d; display: flex; flex-direction: column; gap: 4px; }
.beat { display: flex; align-items: baseline; gap: 8px; font-size: 13px; min-width: 0; }
.beat-ts { color: #6e7681; font-variant-numeric: tabular-nums; flex-shrink: 0; }
.beat-agent { color: #c9d1d9; font-weight: 600; flex-shrink: 0; }
.beat-dot { width: 8px; height: 8px; border-radius: 50%; background: #6e7681; flex-shrink: 0; align-self: center; }
.dot-busy { background: #3fb950; } .dot-idle { background: #8b949e; } .dot-blocked { background: #f85149; } .dot-done { background: #a371f7; }
.beat-msg { color: #8b949e; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
.beats-empty { color: #6e7681; font-size: 13px; margin: 8px 0 0; }
</style>
