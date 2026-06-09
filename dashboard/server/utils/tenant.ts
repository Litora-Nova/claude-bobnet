// Tenant-Auflösung (#9): EIN Dashboard, viele Projekt-Bobiverses.
//
// Modus A (multi-tenant): ?project=<uid> am Request → Registry-Eintrag
//   (projects.registry.json) liefert standup/theme/label/icon/responsibility.
// Modus B (Fallback, backward-kompatibel): KEIN ?project-Param → exakt das
//   heutige Env-Verhalten (NUXT_STANDUP_DIR / NUXT_TEAM_CONFIG) — ein
//   Projekt-Bobiverse ohne Registry läuft unverändert weiter.
//
// Die uid ist der IMMUTABLE Namespace (Registry-Regel); Personas/Namen sind
// Anzeige. Unbekannte uid → 404 (kein stiller Fallback auf ein fremdes Team).
import { resolve } from 'node:path'
import type { H3Event } from 'h3'
import { projectByUid } from './registry.mjs'

export type Tenant = {
  uid: string | null            // null = Env-Fallback-Modus (Modus B)
  standupDir: string            // absolut
  projectRoot: string           // absolut — Repo-Root (wo README/GOAL/ROADMAP liegen)
  teamConfigPath: string        // absolut
  themeId: string | null        // Theme aus der Registry (nur Modus A), sonst null
  label?: string
  icon?: string
  responsibility?: string
}

// Modus B — heutiges Single-Tenant-Verhalten aus Env/runtimeConfig.
export function envTenant(): Tenant {
  const cfg = useRuntimeConfig()
  const standupDir = resolve(process.cwd(), cfg.standupDir as string)
  const teamConfigPath = process.env.NUXT_TEAM_CONFIG
    ? resolve(process.env.NUXT_TEAM_CONFIG)
    : resolve(standupDir, 'team.config.json')
  // Projekt-Root liegt eine Ebene über standup (GOAL.md/ROADMAP.md liegen wie
  // README.md im Repo-Root, nicht im standup-Dir — PO-Entscheid #30).
  const projectRoot = resolve(standupDir, '..')
  return { uid: null, standupDir, projectRoot, teamConfigPath, themeId: null }
}

// Registry-Eintrag → Tenant (auch für /api/projects nutzbar, ohne Event).
export function tenantFromProject(p: any): Tenant {
  // Registry-Regel: jeder Eintrag trägt path (+ optional standup). Fehlt BEIDES,
  // würde resolve('') still im App-cwd landen (falscher Tenant) — hart scheitern
  // ist ehrlicher; /api/projects überspringt solche Einträge (Review-Finding).
  if (!p.standup && !p.path) {
    throw createError({ statusCode: 500, statusMessage: `Registry-Eintrag ohne path/standup: ${p.uid || p.name || '(unbenannt)'}` })
  }
  const standupDir = resolve(p.standup || resolve(String(p.path), '_dev_team/standup'))
  // Projekt-Root (#30): der Registry-`path` ist das Repo-Root (wo GOAL.md/ROADMAP.md
  // wie README.md liegen). Nur-`standup`-Einträge ohne path → eine Ebene über standup
  // (gleiche Heuristik wie Env-Modus).
  const projectRoot = p.path ? resolve(String(p.path)) : resolve(standupDir, '..')
  return {
    uid: p.uid || p.name,
    standupDir,
    projectRoot,
    teamConfigPath: resolve(standupDir, 'team.config.json'),
    themeId: p.theme || null,
    label: p.label || p.name,
    icon: p.icon,
    responsibility: p.responsibility,
  }
}

export function tenantOf(event: H3Event): Tenant {
  const uid = String(getQuery(event).project || '').trim()
  if (!uid) return envTenant()
  const p = projectByUid(uid)
  if (!p) throw createError({ statusCode: 404, statusMessage: `Unbekanntes Projekt: ${uid}` })
  return tenantFromProject(p)
}
