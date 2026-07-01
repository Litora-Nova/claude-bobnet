// Liveness-Probe fuer Supervisor/Monitoring (systemd, Uptime-Checks, Colonel). Bewusst
// tenant-NEUTRAL + abhaengigkeitsfrei: beantwortet nur "laeuft der Node-Server?" — KEIN
// Standup-/Registry-/FS-Zugriff, damit ein gesunder Prozess IMMER 200 liefert, auch wenn
// ein einzelner Tenant kaputt ist. (Schliesst die 404s auf /api/health im Server-Log.)
export default defineEventHandler((event) => {
  setHeader(event, 'Cache-Control', 'no-store')
  return { ok: true, uptime: Math.round(process.uptime()), pid: process.pid, ts: new Date().toISOString() }
})
