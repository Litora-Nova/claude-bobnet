// Geteilte Live-Datenquellen. Stabile useFetch-Keys → Layout + Seiten teilen
// EINEN Cache (kein Doppel-Fetch trotz mehrerer Aufrufer). Zentrales Polling
// lebt im Layout (immer gemountet) und frischt die Keys via refreshNuxtData([…]).
// Mutationen (Status posten, Task adden …) rufen danach selbst refreshNuxtData(key).
//
// Multi-tenant (#9): alle Quellen hängen reaktiv am ?project-Query (useProject) —
// Projekt-Switch refetcht dieselben Keys gegen den neuen Tenant, OHNE Neustart.
export const useStandup = () => useFetch('/api/standup', { key: 'standup', query: useProjectQuery() })
export const useTasks = () => useFetch('/api/tasks', { key: 'tasks', query: useProjectQuery() })
export const useInbox = () => useFetch('/api/inbox', { key: 'inbox', query: useProjectQuery() })
export const useQa = () => useFetch('/api/qa', { key: 'qa', query: useProjectQuery() })
export const usePoTasks = () => useFetch('/api/po-tasks', { key: 'poTasks', query: useProjectQuery() })
// Plan (#30): GOAL.md + ROADMAP.md aus dem Projekt-Root. tenant-reaktiv wie die
// anderen Quellen — stabiler Key 'plan' (zentraler Slow-Poll im Layout).
export const usePlan = () => useFetch('/api/plan', { key: 'plan', query: useProjectQuery() })
// Bobiverse-Übersicht (#9/#10): tenant-NEUTRAL — bewusst OHNE ?project-Query.
export const useProjects = () => useFetch('/api/projects', { key: 'projects' })

// Blockierte Agents (letzter Heartbeat = 'blocked'), abzüglich bereits als Task
// übernommener (Owner+Text) oder dauerhaft aufgelöster — identische Logik wie
// früher in app.vue. Speist das globale Banner (Layout) UND die /tasks-Seite.
export function useBlocked() {
  const { data: standup } = useStandup()
  const { data: tasks } = useTasks()
  // PO-Name aus der Instanz-Config (team.config po.name → public.poName), Fallback
  // 'Owner'. Der PO selbst soll nicht im Blocker-Banner auftauchen (er löst auf).
  const poName = (useRuntimeConfig().public.poName as string) || 'Owner'
  return computed(() => {
    const t = tasks.value as any
    const taken = new Set((t?.tasks || []).map((x: any) => `${x.owner}|${x.text}`))
    const done = new Set(t?.resolved || [])
    return ((standup.value as any)?.agents || []).filter((a: any) => {
      const key = `${a.name}|${a.latest?.msg}`
      return a.name !== poName && a.latest?.status === 'blocked' && !taken.has(key) && !done.has(key)
    })
  })
}
