<script setup lang="ts">
// /bugs — rendert standup/_bugs.md (Produkt-Bug-/QM-Log). Read-only-Ansicht.
useHead({ title: 'Bugs · Stand-up' })
const { data } = await useFetch('/api/bugs', { key: 'bugs' })
</script>

<template>
  <div>
    <div class="page-head">
      <h2><Icon name="mdi:bug-outline" class="ic" /> Bugs · QM-Log</h2>
      <span class="ph-sub">Produkt-Bug-/QM-Log (Bob pflegt · Quelle: Austins Durchklick) — read-only</span>
    </div>
    <section class="panel-box">
      <div v-if="(data as any)?.html" class="md" v-html="(data as any).html"></div>
      <div v-else class="muted">— kein Bug-Log (_bugs.md) gefunden —</div>
    </section>
  </div>
</template>

<style scoped>
/* Einfacher Card-Rahmen um den Markdown (analog .overlay/.sprint-Optik). */
.panel-box { background: #161b22; border: 1px solid #21262d; border-radius: 10px; padding: 6px 18px 18px; margin: 12px 0 22px; }
</style>
