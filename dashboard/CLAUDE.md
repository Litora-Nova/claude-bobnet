# acme-bobiverse — Agent-Onboarding (Garfield-Revier)

Live-Stand-up-Dashboard fürs Bobiverse-Team. Eigenes Repo, liegt physisch unter
`~/Sites/<project>/acme-bobiverse/` aber **separat versioniert** (eigenes `.git`).
Hauptrepo `acme-lms` ignoriert es via `.gitignore` (wie die anderen App-Repos).

## Stack

- **Nuxt 3** (SSR) · TypeScript · keine UI-Lib (handgerolltes CSS, GitHub-Dark-Palette);
  **Icons via `@nuxt/icon`@1 + mdi** (`clientBundle`, nur genutzte Icons inline, svg-Mode,
  kein Egress — neue Icons in `nuxt.config.ts` `icon.clientBundle.icons` ergänzen!).
  Persona-Avatare bleiben Emoji.
- **Node 24** (`.nvmrc`) · `npm` (kein pnpm/yarn)
- **Multi-Page** (seit 2026-06-01, Austin-Wunsch „jeder Bereich eine verlinkbare Seite"):
  `app.vue` = Shell (`<NuxtLayout><NuxtPage/>`), `layouts/default.vue` = Header-Nav +
  globales Blocker-Banner + Footer, `pages/*.vue` = je eine Route (`/`, `/tasks`,
  `/reports`, `/feedback`, `/wishes`, `/qa`, `/briefing`, `/inbox`, `/bugs`, `/approvals`).
  Das generische `components/OverlayPanel.vue` wird von den Panel-Seiten im
  `page`-Mode gehostet (kein Overlay-Toggle mehr). Globale CSS: `assets/css/main.css`.
  Geteilte Live-Daten + zentrales Polling: `composables/useLive.ts` (stabile
  `useFetch`-Keys, Refresh via `refreshNuxtData`). Vor 06-01 war es eine Single-`app.vue`.
- Server-Routen: `server/api/*.ts` (lesen `standup/`-Dateien aus dem **Hauptrepo**)
- Keine DB, keine externen Deps zur Laufzeit — Quelle sind nur Heartbeat-Logs +
  Markdown-Dateien (`standup/{wishes,qa,approvals,feedback}/`, `_bugs.md`, …)

## Konventionen

- **Port hart auf 3030** (siehe `nuxt.config.ts` + Preview-Skript). Wird **nicht** geändert.
- **`standupDir` über `NUXT_STANDUP_DIR`** (NICHT `STANDUP_DIR` — Nuxt-runtimeConfig
  braucht das `NUXT_`-Präfix). Default: `../standup` (relativ zu cwd).
- **Avatare:** `public/avatars/<Name>.png` mit Klar-Namen (z. B. `Bill.png`, `Henry.png`),
  max 512px square, **<80KB** (Bender-Asset-Konsistenz, 2026-05-30-Slim-Sprint).
  Master-Originale (1024+) liegen in `design/avatars/<Name>.png` als Quelle für
  Re-Slim. Pipeline: `sips -Z 512` (oder 384 für große) + `pngquant --quality=70-90 --strip`.
  Globaler Fallback = `public/avatars/default.png` (Anonymous-Maske) für jeden Bob
  ohne eigenes Bild. Emoji greift nur, wenn auch `default.png` fehlt.
- **Roster = Single Source of Truth** in `server/utils/roster.ts` (TEAM.md folgt).
  Externe Coworker (Tim/Henry) tragen `external: true` + `channel: <relpath>` und
  erscheinen nur im Grid, wenn ihre Channel-Datei < 48 h alt ist.
- **Heartbeat-Format:** `YYYY-MM-DD HH:MM | status | msg` (alt `HH:MM | …` bleibt
  rückwärts kompatibel — der Parser akzeptiert beides).
- **Stil:** kompakte HTML-Tags auf 1 Zeile, kurze TS-Files, Kommentare auf Deutsch.

## PWA/Service-Worker ENTFERNT (2026-05-30, Austin-Entscheidung)

PWA war ab 29.05. via `@vite-pwa/nuxt` aktiv (Branch `garfield/pwa-enable`,
master 67a1ead). Am 30.05. 01:34 meldete Austin live: Dashboard zeigt seit
Stunden stale Daten (gestriger Sprint, alte Heartbeats). Root-Cause: Workbox-
`registerType: 'autoUpdate'` + Precache lieferte SSR-HTML CacheFirst. Austin-
Entscheidung danach: **Service-Worker kann komplett weg** — er hatte 0 Nutzen
für uns. Der einzige gewünschte Effekt („Browser fragt installieren") kommt
NICHT vom SW, sondern von Meta-Tags + Manifest. Also: SW raus, Install behalten.

**Install-Fähigkeit OHNE Service-Worker:**
- **iOS „Zum Home-Bildschirm"** läuft rein über die `apple-mobile-web-app-*`-
  Meta-Tags + `apple-touch-icon` (`nuxt.config` `app.head`). Kein Manifest, kein
  SW nötig — iOS A2HS braucht nie einen SW.
- **Chrome/Android „App installieren"** braucht ein echtes Manifest:
  statisches **`public/manifest.webmanifest`** (name/short_name/start_url/
  display:standalone/background+theme_color `#0b0e14`/Icons 192+512+512-maskable)
  + `<link rel="manifest">` und `theme-color`-Meta im `app.head`.
- Manifest ist ein **echtes statisches File** in `public/` (überlebt jede PWA-
  Reste-Entfernung). Verify: `curl :3030/manifest.webmanifest` → 200 +
  `content-type: application/manifest+json` (JSON, nicht HTML-Shell).

**Service-Worker-Stand:**
- `@vite-pwa/nuxt` **restlos raus** aus `package.json` (devDeps) — kein Workbox-
  SW, kein Auto-Manifest wird mehr generiert. **KEIN Re-Enable ohne Austin-Opt-in.**
- `public/sw.js` = selbst-deregistrierender **Kill-Switch** (`install→skipWaiting`,
  `activate→delete alle Caches + unregister + client.navigate`). Befreit Alt-
  Clients (v.a. Austins iPhone) vom früheren Workbox-SW. Wird via `routeRules`
  mit `Cache-Control: no-cache, no-store, must-revalidate` ausgeliefert, damit
  Browser ihn sofort beim nächsten Update-Check abholen statt erst nach ~24h.
  **Retire (Datei löschen) erst wenn alle Clients clean** — frühestens in ein
  paar Tagen. NICHT vorher löschen, sonst kriegt ein Alt-Gerät das Kill-Signal nie.

## Demo-Mode-Vertrag

`?demo=1` → Header anonymisiert (`Team Stand-up` statt `Acme Inc · Stand-up`,
beide mit dem grünen Live-Pulse-Dot davor) + Tasks-Panel zwingend offen +
Austin-Toggle (`👤 Status`) zwingend AN (Roster-Card + Status-Eingabeform sichtbar)
— alles für reproduzierbare Screenshots/Doku/FR. Liest in diesem Mode **kein**
localStorage; revertiert sauber beim Wegnehmen des Query-Params. Wenn ein neues
Feature ein „aufgeräumtes" Verhalten für Screenshots braucht, gehört der Branch
hierher (nicht ins normale UI verschmieren).

## No-Push-Regel (HARTE Regel)

- **NIEMALS** zum `origin` pushen, **NIEMALS** master direkt anfassen ohne Austins ausdrückliches OK.
- Arbeitsmodus: Feature-Branch `garfield/<thema>` lokal, kleine Commits, **lokal lassen**
  bis Austin „push" sagt. Auch dann nicht nach master mergen ohne separates OK.
- Repo ist privat — wenn es jemals public/GitHub geht, vorher Key-Purge wie in
  `~/Sites/<project>/standup/Garfield.log` 2026-05-25 (Tailscale-Key/Cert raus, History gc).

## Dev-Server (eigene App — darf neu gestartet werden)

```bash
lsof -ti tcp:3030 | xargs kill -9 2>/dev/null
bash -lc 'cd ~/Sites/<project>/acme-bobiverse && nvm use && npm run dev'
# Health: curl -s -o /dev/null -w '%{http_code}' localhost:3030  → 200
```

Build-Verify (vor Commit) auf Port 3099, damit :3030 ungestört bleibt:
```bash
npm run build && PORT=3099 node .output/server/index.mjs &
```

## Wer hier wohnt

`Garfield` (Bobiverse-/Dashboard-Maintainer). Scope: alles unter `acme-bobiverse/`
plus **Lesezugriff** `~/Sites/<project>/standup/**`. Schreibrechte im Hauptrepo:
nur eigene Heartbeat-Datei (`standup/Garfield.log` via `standup/log.sh`). Andere
`standup/*.md` (Reports, Feedback, Wünsche) gehören Homer bzw. dem Team — Garfield
flaggt Formatprobleme, fixt sie aber im Parser, nicht in fremden Dateien.
