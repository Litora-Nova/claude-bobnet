// Registry-Layer (#9, #7-ready) — liest projects.registry.json (das Zuständigkeits-
// Verzeichnis des Bobiverse). Bewusst .mjs: direkt per node testbar
// (tests/dashboard_registry_spec.sh), nitro importiert mjs problemlos.
//
// Pfad-Auflösung: NUXT_REGISTRY (explizit) > <cwd>/../../projects.registry.json
// (topologie-robust: Dashboard läuft in <engine>/dashboard, Registry liegt im
// tool-hub-Root NEBEN der Engine — gleiche Auflösung wie bin/start).
//
// Felder je Projekt: uid (immutabler Namespace, Lookup-Key) · name (= Ordnername,
// Primary Key lt. Registry-Regel) · label (Anzeige) · path · standup · theme ·
// status · responsibility (#7) · icon (optional, Austin-Wunsch 2026-06-06).
// Unbekannte Felder werden unverändert durchgereicht — das Schema wächst mit #7.
import { readFileSync, statSync } from 'node:fs'
import { resolve } from 'node:path'

export function registryPath(env = process.env, cwd = process.cwd()) {
  if (env.NUXT_REGISTRY) return resolve(env.NUXT_REGISTRY)
  return resolve(cwd, '../../projects.registry.json')
}

// mtime-gecacht: Registry ändert sich, wenn Projekte (de)registrieren — kein
// Neustart nötig (always-on Hub), aber auch kein Read pro Request.
// (Granularitäts-Hinweis, gilt auch für team.ts/theme.ts: auf FS mit 1s-mtime
// kann ein Sub-Sekunden-Doppel-Edit unentdeckt bleiben — für seltene manuelle
// Config-Edits akzeptiert, Review-Finding 2026-06-06.)
let _cache = { path: '', mtimeMs: -1, data: null }
export function loadRegistry(path = registryPath()) {
  let mtimeMs = 0
  try { mtimeMs = statSync(path).mtimeMs } catch { return { version: 0, projects: [] } }
  if (_cache.data && _cache.path === path && _cache.mtimeMs === mtimeMs) return _cache.data
  let data
  try { data = JSON.parse(readFileSync(path, 'utf8')) } catch { data = null }
  if (!data || !Array.isArray(data.projects)) data = { version: 0, projects: [] }
  _cache = { path, mtimeMs, data }
  return data
}

// Alle Einträge (Konsument filtert z. B. auf status==='active').
export const listProjects = (path) => loadRegistry(path).projects

// uid bevorzugt (immutabel); name nur als Fallback solange ein Eintrag (noch)
// keine uid trägt — gleiche Semantik wie der Launcher.
export function projectByUid(uid, path) {
  if (!uid) return null
  for (const p of loadRegistry(path).projects) {
    if (p.uid === uid || (!p.uid && p.name === uid)) return p
  }
  return null
}
