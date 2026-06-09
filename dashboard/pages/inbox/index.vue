<script setup lang="ts">
// Inbox-Index (/inbox): die letzten 42 Heartbeats des PO — Default der "Meine Page",
// wenn keine Unterseite gewählt ist (HeartbeatList-Komponente, PO-Wunsch).
// PO-Name aus der Instanz-Config (team.config po.name → public.poName), Fallback 'Owner'.
const poName = (useRuntimeConfig().public.poName as string) || 'Owner'
useHead({ title: 'Inbox · Meine Heartbeats · Stand-up' })
</script>

<template>
  <div>
    <div class="page-head">
      <h2><Icon name="mdi:heart-pulse" class="ic" /> Meine letzten Heartbeats</h2>
      <span class="ph-sub">letzte 42 · neueste zuerst</span>
    </div>
    <HeartbeatList :agent="poName" :limit="42" />
  </div>
</template>
