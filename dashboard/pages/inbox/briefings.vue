<script setup lang="ts">
// /inbox/briefings — die Briefing-Doku des PO (standup/po.tasks.md, Legacy:
// austin.tasks.md), Markdown-Tasks mit Click-Expand. OverlayPanel-kind 'tasks'.
// Unterseite des Inbox-Hubs.
useHead({ title: 'Inbox · Briefings · Stand-up' })
</script>

<template>
  <OverlayPanel kind="tasks" />
</template>
