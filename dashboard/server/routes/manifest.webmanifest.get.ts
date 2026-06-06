import { getCookie } from 'h3'
import { projectByUid } from '../utils/registry.mjs'
import { envTenant, tenantFromProject } from '../utils/tenant'
import { teamOf } from '../utils/team'

// Dynamisches PWA-Manifest (#9, ersetzt das statische public/manifest.webmanifest):
// Name/Kurzname kommen zur Laufzeit aus dem AKTIVEN Tenant — der Browser schickt
// das bobnet-project-Cookie beim Manifest-Fetch mit. Ohne aktives Projekt:
// Env-Tenant (heutiges Verhalten), ganz ohne Config → Hub-Branding "BobNet".
// Rest (Icons/Farben/Display) wie das bisherige statische Manifest.
export default defineEventHandler((event) => {
  const uid = String(getCookie(event, 'bobnet-project') || '').trim()
  const p = uid ? projectByUid(uid) : null
  const tenant = p ? tenantFromProject(p) : envTenant()
  const cfg = teamOf(tenant).config

  const name = cfg.title || tenant.label || 'BobNet'
  const shortName = cfg.shortTitle || (cfg.title ? cfg.title.split('·')[0].trim() : 'BobNet')

  setHeader(event, 'Content-Type', 'application/manifest+json')
  // Tenant-abhängig → nicht teilen/cachen über Nutzer hinweg; kurzes private-Cache reicht.
  setHeader(event, 'Cache-Control', 'private, max-age=300')
  return {
    name,
    short_name: shortName,
    start_url: '/',
    display: 'standalone',
    background_color: '#0b0e14',
    theme_color: '#0b0e14',
    icons: [
      { src: '/pwa-192.png', sizes: '192x192', type: 'image/png', purpose: 'any' },
      { src: '/pwa-512.png', sizes: '512x512', type: 'image/png', purpose: 'any' },
      { src: '/pwa-512-maskable.png', sizes: '512x512', type: 'image/png', purpose: 'maskable' },
    ],
  }
})
