<script setup lang="ts">
// /tasks: interaktive Quick-Tasks (Austin) + Blocker-Übernahme. Eigene Seite seit
// dem Multi-Page-Umbau (Austin-Wunsch 2026-06-01). Das globale Blocker-Banner im
// Layout verlinkt hierher ('+ als Task' lebt hier). Quelle: /api/tasks + blocked.

useHead({ title: 'Tasks · Stand-up' })

const { data: tasks } = await useTasks()
const blocked = useBlocked()

// Tenant-aware (#13): die GET-Quelle (useTasks) hängt schon am ?project. ALLE
// schreibenden Calls hier (heartbeat/notify/resolve/tasks) sind serverseitig
// tenantOf-gescoped → ohne ?project landen sie im Launcher-Projekt statt im
// aktiven Tenant. Darum jeden POST mit dem aktiven Projekt-Query versehen.
const projectQuery = useProjectQuery()
const projectParam = () => projectQuery.value   // {} oder { project }

type Task = { id: number; state: 'open' | 'doing' | 'done'; done: boolean; text: string; owner: string }
const newTask = ref('')

// Abhaken = erledigt: Austin-Heartbeat, Owner 1× pingen, Blocker dauerhaft als
// erledigt merken (sonst kommt ein schlafender Agent wieder als 'blocked' hoch),
// dann aus der Liste entfernen.
async function completeTask(t: Task) {
  await $fetch('/api/heartbeat', { method: 'POST', query: projectParam(), body: { agent: 'Austin', status: 'done', msg: `✔ ${t.text}` } })
  if (t.owner) {
    await $fetch('/api/notify', { method: 'POST', query: projectParam(), body: { agent: t.owner, msg: `✔ erledigt: "${t.text}" — leg los` } })
    await $fetch('/api/resolve', { method: 'POST', query: projectParam(), body: { agent: t.owner, blocker: t.text } })
  }
  await $fetch('/api/tasks', { method: 'POST', query: projectParam(), body: { action: 'remove', id: t.id } })
  refreshNuxtData(['tasks', 'standup'])
}

// Zustands-Pill: zyklisch [ ]→[~]→[x]→[ ].
const STATE_NEXT: Record<Task['state'], string> = { open: 'mach ich grad', doing: 'fertig', done: 'wieder offen' }
async function cycleTask(t: Task) {
  await $fetch('/api/tasks', { method: 'POST', query: projectParam(), body: { action: 'toggle', id: t.id } })
  refreshNuxtData('tasks')
}
async function addTask() {
  const text = newTask.value.trim()
  if (!text) return
  await $fetch('/api/tasks', { method: 'POST', query: projectParam(), body: { action: 'add', text } })
  newTask.value = ''
  refreshNuxtData('tasks')
}
async function doTaskNow(text: string) {       // Task → aktueller Austin-Heartbeat
  await $fetch('/api/heartbeat', { method: 'POST', query: projectParam(), body: { agent: 'Austin', status: 'busy', msg: text } })
  refreshNuxtData('standup')
}
// Blocker als Task übernehmen (ohne Nachricht) — der Ping passiert erst beim Abhaken.
async function blockToTask(a: any) {
  await $fetch('/api/tasks', { method: 'POST', query: projectParam(), body: { action: 'add', text: `@${a.name} ${a.latest?.msg || 'Blocker auflösen'}` } })
  refreshNuxtData('tasks')
}
</script>

<template>
  <div>
    <div class="page-head">
      <h2><Icon name="mdi:pin" class="ic" /> Tasks · Austin</h2>
      <span class="ph-sub">{{ (tasks as any)?.tasks?.length || 0 }} Tasks<span v-if="blocked.length"> · {{ blocked.length }} blockiert</span></span>
    </div>

    <section class="tasks">
      <ul v-if="blocked.length" class="urgent">
        <li v-for="a in blocked" :key="a.name">
          <span class="badge"><Icon name="mdi:alert" class="ic" /> blockiert</span>
          <span class="b-agent">{{ a.name }}</span>
          <span class="b-msg">{{ a.latest?.msg }}</span>
          <button class="now-btn" @click="blockToTask(a)" :title="`Als Task übernehmen — @${a.name} wird erst beim Abhaken gepingt`"><Icon name="mdi:plus" class="ic" /> als Task</button>
        </li>
      </ul>

      <ul class="tasklist">
        <li v-for="t in (tasks as any)?.tasks" :key="t.id" :class="t.state">
          <button class="state" :class="t.state" @click="cycleTask(t)" :title="`Zustand: ${t.state} — klicken: ${STATE_NEXT[t.state as Task['state']]}`"><Icon v-if="t.state==='done'" name="mdi:check" /><Icon v-else-if="t.state==='doing'" name="mdi:circle-half-full" /><span v-else></span></button>
          <span v-if="t.owner" class="owner">@{{ t.owner }}</span>
          <span class="ttext">{{ t.text }}</span>
          <button class="now-btn" @click="doTaskNow(t.text)" title="Als aktuellen Heartbeat eintragen"><Icon name="mdi:play" class="ic" /> mach ich jetzt</button>
          <button class="done-btn" @click="completeTask(t)" :title="t.owner ? `Erledigt + @${t.owner} pingen + aus Liste entfernen` : 'Erledigt + aus Liste entfernen'"><Icon name="mdi:check" class="ic" /> erledigt</button>
        </li>
        <li v-if="!(tasks as any)?.tasks?.length" class="muted">— keine Tasks —</li>
      </ul>
      <form class="addtask" @submit.prevent="addTask">
        <input v-model="newTask" placeholder="Neue Aufgabe …  (Tipp: @Bill voranstellen für Zuständigkeit)" />
        <button type="submit"><Icon name="mdi:plus" class="ic" /> Task</button>
      </form>
    </section>
  </div>
</template>
