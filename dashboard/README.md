# Acme Stand-up · Live-Dashboard

Schlankes Nuxt-3-Dashboard, das **live** zeigt, woran jeder Team-Agent gerade
arbeitet — gespeist aus Heartbeat-Logs, die die Agents selbst schreiben.

## Start
```bash
cd acme-bobiverse
npm install
npm run dev          # → http://localhost:3030
```
(Server startet **der User** selbst — Agents starten keine Dev-Server.)

## Wie es funktioniert
- Jeder Agent hängt **vor jedem Arbeitsschritt** eine Zeile an seine eigene
  Heartbeat-Datei an — über das Helfer-Skript im acme-docs-Repo:
  ```bash
  $HOME/Sites/<project>/standup/log.sh <Agent> <status> "<was ich jetzt tue>"
  # status: busy | idle | blocked | done
  ```
  Eine Datei pro Agent (`standup/<Agent>.log`) → keine Schreibkonflikte.
- Die Server-Route `server/api/standup.get.ts` liest den Ordner `../standup`,
  nimmt pro Agent die **letzten 3** Zeilen und liefert sie als JSON.
- `app.vue` pollt alle 3 s und rendert Tabelle + Sprint-Ziele (`standup/_sprint.md`).

## Token-arm
Schreibseite = eine kurze Zeile pro Agent-Schritt. Sonst keine laufenden Kosten.

## Aufs Handy holen (Tailscale Serve)
Das Dashboard läuft nur lokal auf :3030. Über **Tailscale Serve** wird es sicher im
eigenen Tailnet erreichbar (nicht öffentlich) — ideal fürs Mitschauen vom Handy.

**Einmalig im Tailscale-Admin aktivieren** — sonst *startet* `serve` zwar, aber das
Handy bekommt einen TLS-/Zertifikatsfehler (das war der Stolperstein):
- https://login.tailscale.com/admin/dns → **MagicDNS** an **und** **HTTPS Certificates** („Enable HTTPS") an.

Dann auf dem Mac (wo :3030 läuft):
```bash
tailscale serve --bg 3030
tailscale serve status     # zeigt die URL, z.B. https://<mac>.<tailnet>.ts.net/
```
Erstes Laden kann ~10 s dauern (das Cert wird ausgestellt). Am Handy: Tailscale-App
im **selben Tailnet** verbinden → die URL aus `serve status` öffnen.

Stoppen: `tailscale serve reset`. Öffentlich (statt nur im Tailnet) ginge
`tailscale funnel` — aber **nur mit Login davor**, das Dashboard hat keine Auth.

## PWA (Home-Screen / Dock)

Das Dashboard ist eine **installierbare PWA** (`@vite-pwa/nuxt`). iOS Safari → „Zum
Home-Bildschirm hinzufügen", macOS Chrome/Brave → Adressleiste → Install-Icon,
Android Chrome → „App installieren".

**Icon austauschen** (Austin liefert custom Bobiverse-Icon nach):
- `public/pwa-192.png` — 192×192 PNG (Android Home-Screen)
- `public/pwa-512.png` — 512×512 PNG (Splash + Android Hi-Res)
- `public/pwa-512-maskable.png` — 512×512 PNG mit **Safe-Zone in den inneren ~80%**
  (Android maskiert auf Kreis/Squircle — alles Wichtige innerhalb des Inner-Circles)
- `public/apple-touch-icon.png` — 180×180 PNG (iOS Home-Screen, kein Maskieren)
- `public/favicon.ico` — Multi-Size .ico (Browser-Tab)

Nach Tausch: `npm run build` (oder HMR im `npm run dev`) zieht die neuen Files
automatisch ins Manifest. Service-Worker macht `autoUpdate` → User bekommt das
Update beim nächsten Open ohne Cache-Bust.

> Eigenes Verzeichnis, im acme-docs-Parent via `.gitignore` ausgeschlossen
> (wie die anderen App-Repos). Reines internes Tooling, `noindex`.
