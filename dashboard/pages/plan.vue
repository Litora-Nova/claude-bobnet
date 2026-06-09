<script setup lang="ts">
// /plan (#30) — Goal + Roadmap pro Projekt, gerendert aus GOAL.md/ROADMAP.md im
// Projekt-Root (sichtbare Repo-Struktur wie README.md, PO-Entscheid). tenant-aware
// über usePlan() (hängt reaktiv am ?project). GOAL steht oben & prominent: fehlt es,
// kommt ein deutlicher roter Alert ("kein Kompass") — derselbe empty-Zustand speist
// das Nav-Badge "!" im Layout, damit der fehlende Goal von JEDER Seite sichtbar ist.
useHead({ title: 'Plan · Stand-up' })
const { data } = usePlan()
const goal = computed(() => (data.value as any)?.goal || { html: '', empty: true })
const roadmap = computed(() => (data.value as any)?.roadmap || { html: '', empty: true })
</script>

<template>
  <div>
    <div class="page-head">
      <h2><Icon name="mdi:flag-checkered" class="ic" /> Plan · Goal &amp; Roadmap</h2>
      <span class="ph-sub">Goal &amp; Roadmap aus dem Projekt-Root (GOAL.md / ROADMAP.md) — read-only</span>
    </div>

    <!-- GOAL prominent oben. Fehlt es → roter Alert (kein Kompass für den Plan-Richter). -->
    <section class="plan-goal">
      <h3 class="plan-label"><Icon name="mdi:target" class="ic" /> Goal</h3>
      <div v-if="goal.empty" class="goal-alert">
        <Icon name="mdi:alert" class="goal-alert-icon" />
        <div class="goal-alert-body">
          <strong>GOAL fehlt</strong> — bitte <code>GOAL.md</code> im Projekt-Root anlegen.
          Ohne Goal kein Kompass (der Plan-Richter/Anek prüft dagegen).
        </div>
      </div>
      <div v-else class="panel-box goal-box"><div class="md" v-html="goal.html"></div></div>
    </section>

    <!-- ROADMAP darunter. Leer → dezenter Hinweis. -->
    <section class="plan-roadmap">
      <h3 class="plan-label"><Icon name="mdi:map-marker-path" class="ic" /> Roadmap</h3>
      <div v-if="roadmap.empty" class="muted plan-roadmap-empty">— noch keine ROADMAP.md —</div>
      <div v-else class="panel-box"><div class="md" v-html="roadmap.html"></div></div>
    </section>
  </div>
</template>

<style scoped>
/* Card-Rahmen um den Markdown (analog .overlay/.sprint-Optik, wie /bugs). */
.panel-box { background: #161b22; border: 1px solid #21262d; border-radius: 10px; padding: 6px 18px 18px; margin: 12px 0 22px; }
.plan-label { display: flex; align-items: center; gap: 7px; font-size: 14px; color: #e6edf3; margin: 18px 0 0; text-transform: uppercase; letter-spacing: .04em; }
.plan-label .ic { font-size: 17px; }
/* GOAL etwas hervorgehoben: linker Akzent-Strich (Blau = Kompass). */
.goal-box { border-left: 3px solid #58a6ff; }
/* Fehlender Goal: deutlicher roter Alert (analog .banner, aber als Block in der Seite). */
.goal-alert { display: flex; align-items: flex-start; gap: 11px; margin: 12px 0 22px; padding: 13px 16px; background: #2d1416; border: 1px solid #f8514955; border-left: 3px solid #f85149; border-radius: 10px; }
.goal-alert-icon { flex: 0 0 auto; font-size: 22px; color: #f85149; margin-top: 1px; }
.goal-alert-body { color: #c9d1d9; font-size: 13px; line-height: 1.5; }
.goal-alert-body strong { color: #f85149; }
.goal-alert-body code { background: #0d1117; border: 1px solid #30363d; border-radius: 4px; padding: 1px 5px; font-size: 12px; color: #e6edf3; }
.plan-roadmap-empty { margin: 12px 0 22px; font-size: 13px; }
</style>
