// Aktives Projekt (#9): null/leer = Env-Modus (heutiges Single-Tenant-Verhalten).
// Persistiert als Cookie (SSR-tauglich, kein Hydration-Flackern wie localStorage).
// Der Switch läuft OHNE Neustart: alle useLive-Fetches hängen reaktiv am
// ?project-Query (useFetch refetcht bei Query-Änderung, Keys bleiben stabil).
export const useActiveProject = () =>
  useCookie<string | null>('bobnet-project', { default: () => null, sameSite: 'lax' })

export const useProjectQuery = () => {
  const active = useActiveProject()
  return computed(() => (active.value ? { project: active.value } : {}))
}

// Avatar-URL tenant-aware. Bild-only-Regel unberührt: der Server liefert IMMER
// ein Bild (Persona → Theme-Default → statisches default.png im Client-Fallback).
export const avatarUrl = (name: string): string => {
  const active = useActiveProject()
  const q = active.value ? `?project=${encodeURIComponent(active.value)}` : ''
  return `/theme-avatar/${encodeURIComponent(name)}${q}`
}
