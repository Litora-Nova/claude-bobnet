<script setup lang="ts">
// Inbox-Index (/inbox): Austins letzte 42 Heartbeats — Default der "Meine Page",
// wenn keine Unterseite gewählt ist (HeartbeatList-Komponente, Austin-Wunsch).
useHead({ title: 'Inbox · Meine Heartbeats · Stand-up' })
</script>

<template>
  <div>
    <div class="page-head">
      <h2><Icon name="mdi:heart-pulse" class="ic" /> Meine letzten Heartbeats</h2>
      <span class="ph-sub">letzte 42 · neueste zuerst</span>
    </div>
    <HeartbeatList agent="Austin" :limit="42" />
  </div>
</template>
