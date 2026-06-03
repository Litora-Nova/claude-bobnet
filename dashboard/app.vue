<script setup lang="ts">
// App-Root = nur Shell. Globale Styles liegen seit dem Multi-Page-Umbau
// (2026-06-01) in assets/css/main.css (via nuxt.config css:[]), nicht mehr hier.
// Routing-Umbau: die früheren Overlay-Panels sind jetzt echte Seiten unter pages/.
// Jede Seite ist verlinkbar (z. B. :3030/approvals) — Austins Wunsch.
</script>

<template>
  <NuxtLayout>
    <NuxtPage />
  </NuxtLayout>
</template>
