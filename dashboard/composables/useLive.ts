// Geteilte Live-Datenquellen. Stabile useFetch-Keys → Layout + Seiten teilen
// EINEN Cache (kein Doppel-Fetch trotz mehrerer Aufrufer). Zentrales Polling
// lebt im Layout (immer gemountet) und frischt die Keys via refreshNuxtData([…]).
// Mutationen (Status posten, Task adden …) rufen danach selbst refreshNuxtData(key).
export const useStandup = () => useFetch('/api/standup', { key: 'standup' })
export const useTasks = () => useFetch('/api/tasks', { key: 'tasks' })
export const useInbox = () => useFetch('/api/inbox', { key: 'inbox' })
export const useQa = () => useFetch('/api/qa', { key: 'qa' })
export const useAustinTasks = () => useFetch('/api/austin-tasks', { key: 'austinTasks' })

// Blockierte Agents (letzter Heartbeat = 'blocked'), abzüglich bereits als Task
// übernommener (Owner+Text) oder dauerhaft aufgelöster — identische Logik wie
// früher in app.vue. Speist das globale Banner (Layout) UND die /tasks-Seite.
export function useBlocked() {
  const { data: standup } = useStandup()
  const { data: tasks } = useTasks()
  return computed(() => {
    const t = tasks.value as any
    const taken = new Set((t?.tasks || []).map((x: any) => `${x.owner}|${x.text}`))
    const done = new Set(t?.resolved || [])
    return ((standup.value as any)?.agents || []).filter((a: any) => {
      const key = `${a.name}|${a.latest?.msg}`
      return a.name !== 'Austin' && a.latest?.status === 'blocked' && !taken.has(key) && !done.has(key)
    })
  })
}
