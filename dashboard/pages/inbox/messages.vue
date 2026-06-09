<script setup lang="ts">
// /inbox/messages — Team-Messages: Austin postet eine Zeile an @Bob/@team/@<Name>
// (notify.post.ts → standup/_inbox.md) + Liste der letzten Nachrichten. Unterseite
// des Inbox-Hubs (2026-06-01).
useHead({ title: 'Inbox · Messages · Stand-up' })

const { data: inbox } = await useInbox()

// Tenant-aware (#13): die GET-Quelle (useInbox) hängt schon am ?project. Der
// POST notify.post.ts ist serverseitig tenantOf-gescoped → ohne ?project landet
// die Nachricht im Launcher-_inbox.md statt im aktiven Tenant. projectParam() =
// Snapshot auf das reaktive Query (imperatives $fetch).
const projectQuery = useProjectQuery()
const projectParam = () => projectQuery.value   // {} oder { project }

const postTarget = ref('Bob')
const postMsg = ref('')
async function postToTeam() {
  const msg = postMsg.value.trim()
  if (!msg) return
  await $fetch('/api/notify', { method: 'POST', query: projectParam(), body: { agent: postTarget.value, msg } })
  postMsg.value = ''
  refreshNuxtData('inbox')
}
</script>

<template>
  <div>
    <div class="page-head">
      <h2><Icon name="mdi:email-outline" class="ic" /> Messages</h2>
      <span class="ph-sub">Posts ans Team (@team / @dev / @Name) → landen im Inbox</span>
    </div>

    <section class="inbox">
      <form class="postbox" @submit.prevent="postToTeam">
        <span class="pb-label"><Icon name="mdi:send" class="ic" /> An:</span>
        <select v-model="postTarget"><option>Bob</option><option>team</option><option>Bill</option><option>Luke</option><option>Linus</option><option>Riker</option><option>Marvin</option><option>Dexter</option><option>Bender</option><option>Garfield</option><option>Homer</option><option>Bridget</option><option>Mario</option><option>Tim</option><option>Henry</option></select>
        <input v-model="postMsg" :placeholder="`Nachricht an @${postTarget} … (landet im Inbox)`" />
        <button type="submit">Senden</button>
      </form>
      <ul class="inboxlist">
        <li v-for="m in (inbox as any)?.items" :key="m.id"><span class="ts">{{ m.ts }}</span> <span class="i-target">{{ m.target }}</span> <span class="i-msg">{{ m.msg }}</span></li>
        <li v-if="!(inbox as any)?.items?.length" class="muted">— Inbox leer —</li>
      </ul>
    </section>
  </div>
</template>
