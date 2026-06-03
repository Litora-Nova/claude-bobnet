// BobNet – schlankes Live-Dashboard für Tech-Lead-orchestrierte Agent-Teams (claude-dev-team).
// Config-driven: Titel/Team/PO kommen aus der Projekt-Instanz (team.config.json), nicht hardcoded.
// Liest Heartbeat-Logs aus <standupDir>. Nur Dev/intern, noindex.
import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'

function teamConfig(): any {
  try {
    const p = process.env.NUXT_TEAM_CONFIG
      || resolve(process.cwd(), process.env.NUXT_STANDUP_DIR || process.env.STANDUP_DIR || '../standup', 'team.config.json')
    return JSON.parse(readFileSync(p, 'utf8'))
  } catch { return {} }
}
const tc = teamConfig()
const TITLE = tc.title || 'Stand-up'
const SHORT = tc.shortTitle || tc.title || 'Stand-up'
const PO_NAME = (tc.po && tc.po.name) || 'Austin'
const ALLOWED = (process.env.NUXT_ALLOWED_HOSTS || '').split(',').map((s: string) => s.trim()).filter(Boolean)

export default defineNuxtConfig({
  ssr: true,
  devtools: { enabled: false },
  // Übers Handy via Tailscale (HTTPS-Proxy auf :3030): an alle Interfaces binden
  // und den Tailnet-Host bei Vite erlauben (sonst 403 "host not allowed").
  // Port 3030 auch in der Config — so startet `nuxi dev` ohne Skript-Flag
  // konsistent (sonst Default 3000).
  devServer: { host: '0.0.0.0', port: 3030 },
  vite: { server: { allowedHosts: ALLOWED } },
  // PWA/Service-Worker ENTFERNT 2026-05-30 (Austin-Entscheidung): @vite-pwa/nuxt
  // restlos raus (kein Workbox-SW, kein Auto-Manifest mehr). Install-Fähigkeit
  // bleibt erhalten — komplett OHNE SW: iOS „Zum Home-Bildschirm" via apple-meta-
  // tags unten, Chrome/Android „App installieren" via statischem
  // public/manifest.webmanifest + <link rel=manifest> unten. Der alte Stale-Cache-
  // Schmerz kam vom Workbox-Precache; ohne SW kann das nicht mehr passieren.
  // KEIN @vite-pwa Re-Enable ohne Austin-Opt-in.
  // (public/sw.js bleibt vorerst als selbst-deregistrierender Kill-Switch, der
  //  Alt-Clients vom früheren Workbox-SW befreit — no-cache via routeRules unten.)
  // @nuxt/icon: mdi (Material Design Icons) via Iconify (2026-06-01, Austin-Wunsch).
  // serverBundle bündelt die mdi-Collection serverseitig (offline-tauglich, kein
  // Runtime-API-Call) — der Client lädt nur die tatsächlich genutzten Icons nach.
  modules: ['@nuxt/icon'],
  // appManifest aus: unsere routeRules-Redirects laufen server-seitig (Nitro);
  // das Client-App-Manifest brauchen wir nicht und es triggert in Dev sonst
  // "Failed to resolve import #app-manifest". (Kein Client-Side-Route-Rule-Bedarf.)
  experimental: { appManifest: false },
  // NUR die tatsächlich genutzten mdi-Icons inline bündeln (clientBundle.icons) —
  // KEIN Full-Collection-Bundle (7000 Icons hängt/ist zu schwer) und KEIN Runtime-
  // Fetch zur Iconify-CDN (Egress/Datensparsamkeit). svg-Mode → inline-<svg> im SSR.
  // Icons erben currentColor (Active-Blau in der Nav, Rot im Banner). Neue Icons:
  // Name hier ergänzen, sonst rendern sie nicht.
  icon: {
    mode: 'svg',
    clientBundle: {
      icons: [
        'mdi:account-group', 'mdi:format-list-checks', 'mdi:file-document-outline',
        'mdi:message-text-outline', 'mdi:star-outline', 'mdi:help-circle-outline',
        'mdi:clipboard-text-outline', 'mdi:inbox-arrow-down', 'mdi:bug-outline',
        'mdi:check-decagram-outline', 'mdi:alert', 'mdi:run', 'mdi:information-outline',
        'mdi:account', 'mdi:play', 'mdi:check', 'mdi:check-circle', 'mdi:circle-half-full',
        'mdi:plus', 'mdi:pin', 'mdi:send', 'mdi:rocket-launch', 'mdi:source-merge',
        'mdi:clipboard-text', 'mdi:close', 'mdi:chevron-down', 'mdi:chevron-right',
        'mdi:arrow-left', 'mdi:account-voice', 'mdi:chart-box-outline',
        'mdi:sort', 'mdi:comment-account-outline', 'mdi:restore',
        'mdi:book-information-variant', 'mdi:heart-pulse', 'mdi:email-outline',
        // Phase F (category-driven Display): Service-Leiste + Helfer-Badges.
        'mdi:server-network', 'mdi:spider', 'mdi:satellite-variant', 'mdi:robot-outline',
      ],
    },
  },
  // Globale Stylesheet (aus app.vue extrahiert beim Multi-Page-Umbau 2026-06-01).
  // GitHub-Dark-Palette + alle geteilten Komponenten-Klassen + Mobile-Media-Queries.
  css: ['~/assets/css/main.css'],
  // Kill-Switch /sw.js MUSS sofort revalidiert werden (sonst hält der Browser ihn
  // bis zu ~24h und Alt-Clients kriegen das Deregister-Signal verspätet).
  routeRules: {
    '/sw.js': { headers: { 'Cache-Control': 'no-cache, no-store, must-revalidate' } },
    // Feedback/Wünsche sind Tabs unter /reports (Austin 2026-06-01). Alte/geteilte
    // Links bleiben gültig → Server-Redirect auf den passenden Tab (kein Client-
    // navigateTo, das sonst #app-manifest in Dev triggert).
    '/feedback': { redirect: '/reports?tab=feedback' },
    '/wishes': { redirect: '/reports?tab=wishes' },
    // Nav-Umbau 2026-06-01: Q&A→Docs; Tasks/Briefing/Approvals als Inbox-Subpages.
    // Alte/geteilte Links bleiben gültig.
    '/qa': { redirect: '/docs' },
    '/tasks': { redirect: '/inbox/tasks' },
    '/briefing': { redirect: '/inbox/briefings' },
    '/approvals': { redirect: '/inbox/approvals' }
  },
  runtimeConfig: {
    // Pfad relativ zum App-Root; per NUXT_STANDUP_DIR (oder STANDUP_DIR) überschreibbar.
    standupDir: process.env.NUXT_STANDUP_DIR || process.env.STANDUP_DIR || '../standup',
    public: {
      // Titel/PO fürs Frontend (Layout/Pages) — aus team.config, per NUXT_PUBLIC_* überschreibbar.
      title: TITLE,
      brand: tc.brand || TITLE.split('·')[0].trim(),
      demoTitle: tc.demoTitle || 'Team Stand-up',
      poName: PO_NAME
    }
  },
  app: {
    head: {
      title: TITLE,
      // viewport: Pflicht fürs Handy — ohne width=device-width zoomt iOS Safari
      // die Desktop-Breite raus und alles wird winzig.
      viewport: 'width=device-width, initial-scale=1',
      meta: [
        { name: 'robots', content: 'noindex' },
        // iOS-PWA-Bits: ohne diese 2 Tags landet die App im Safari-Wrapper statt
        // im Standalone-Mode wenn Austin sie auf den Home-Screen legt.
        { name: 'apple-mobile-web-app-capable', content: 'yes' },
        { name: 'apple-mobile-web-app-status-bar-style', content: 'black-translucent' },
        { name: 'apple-mobile-web-app-title', content: SHORT },
        // theme-color = UI-Chrome-Farbe im Standalone/Install-Mode (Apple-Slate-Dark).
        { name: 'theme-color', content: '#0b0e14' }
      ],
      link: [
        // ICO Legacy zuerst (Browser-Convention), dann moderne PNG-32.
        { rel: 'icon', type: 'image/x-icon', href: '/favicon.ico' },
        { rel: 'icon', type: 'image/png', sizes: '32x32', href: '/favicon-32.png' },
        { rel: 'apple-touch-icon', sizes: '180x180', href: '/apple-touch-icon.png' },
        // Statisches Manifest (kein SW nötig) → Chrome/Android „App installieren".
        { rel: 'manifest', href: '/manifest.webmanifest' }
      ]
    }
  }
})
