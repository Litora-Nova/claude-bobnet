// Heartbeat-Zeilen-Parser — EIN geteilter, PURER Parser für standup.get.ts,
// heartbeats.get.ts und projects.get.ts (vorher dreifach kopiert; .mjs = direkt
// per node testbar, siehe tests/dashboard_beats_spec.sh).
//
// Order ({HUMAN} 2026-06-06, Pre-main-Fix): kompletten Zeitstempel nutzen.
//   • ISO-Zeilen "YYYY-MM-DD HH:MM | status | msg": epoch über die TEAM-Zeitzone
//     (env DEV_TEAM_TZ, Default Europe/Berlin) — NICHT Date.UTC: log.sh schreibt
//     lokale Wandzeit, die UTC-Deutung machte Beats um den Offset „frischer" und
//     verzerrte die Aktivitäts-Fenster (#10, Review-Finding).
//   • Datumslose Alt-Zeilen "HH:MM | …": der Tag ist UNBEKANNT. Nur die LETZTE
//     Zeile einer Datei darf den mtime-Anker beanspruchen (ihr Schreibmoment IST
//     die mtime); alle früheren sind STALE (epoch 0) — eine alte „14:36" darf
//     eine heutige „10:36" nie schlagen (Live-Symptom in der Flotten-Übersicht).
//   • Unparsebare Zeilen: konservativ stale.

export const DEFAULT_TZ = 'Europe/Berlin'
export const teamTz = (env = process.env) => env.DEV_TEAM_TZ || DEFAULT_TZ

// Lokale Wandzeit in `tz` → UTC-Epoch (ms). Doppel-Pass: Offset am Schätzpunkt
// bestimmen, anwenden, am Ergebnis erneut bestimmen — korrekt über DST-Wechsel.
export function zonedEpoch(y, mo, d, h, mi, tz = DEFAULT_TZ) {
  const wall = Date.UTC(y, mo - 1, d, h, mi)
  const offAt = (t) => {
    const p = Object.fromEntries(new Intl.DateTimeFormat('en-US', {
      timeZone: tz, year: 'numeric', month: '2-digit', day: '2-digit',
      hour: '2-digit', minute: '2-digit', second: '2-digit', hour12: false,
    }).formatToParts(new Date(t)).map(x => [x.type, x.value]))
    return Date.UTC(+p.year, +p.month - 1, +p.day, (+p.hour) % 24, +p.minute, +p.second) - t
  }
  let epoch = wall - offAt(wall)
  epoch = wall - offAt(epoch)
  return epoch
}

// Eine Heartbeat-Zeile parsen.
//   line: "ts | status | msg…" · fileMtimeMs: mtime der Log-Datei ·
//   opts.tz: Team-Zeitzone · opts.isLast: ist dies die LETZTE Zeile der Datei?
// Liefert { tsRaw, date ('' wenn datumslos), time ("HH:MM" Anzeige), status,
//           msg, epoch (UTC ms; 0 = stale), stale }.
export function parseBeatLine(line, fileMtimeMs, opts = {}) {
  const { tz = DEFAULT_TZ, isLast = false } = opts
  const [tsRaw, status, ...rest] = line.split('|').map(s => s.trim())
  const ts = tsRaw || ''
  const out = { tsRaw: ts, date: '', time: ts, status: status || '', msg: rest.join(' | '), epoch: 0, stale: false }

  const iso = ts.match(/^(\d{4}-\d{2}-\d{2})[ T](\d{2}):(\d{2})$/)
  if (iso) {
    out.date = iso[1]
    out.time = `${iso[2]}:${iso[3]}`
    out.epoch = zonedEpoch(+iso[1].slice(0, 4), +iso[1].slice(5, 7), +iso[1].slice(8, 10), +iso[2], +iso[3], tz)
    return out
  }

  const hm = ts.match(/^(\d{2}):(\d{2})$/)
  if (hm) {
    if (isLast) out.epoch = fileMtimeMs          // Schreibmoment = mtime; HH:MM bleibt Anzeige
    else { out.stale = true; out.epoch = 0 }     // Tag unbekannt → nie „frisch"
    return out
  }

  out.stale = true
  out.epoch = 0
  return out
}

// Komfort: die letzten N Zeilen einer Log-Datei parsen (Datei-Reihenfolge,
// NICHT reversed) — kapselt die isLast-Regel an einer Stelle.
export function parseTail(lines, fileMtimeMs, opts = {}) {
  const n = opts.limit ?? lines.length
  const tail = lines.slice(-n)
  const lastIdx = tail.length - 1
  return tail.map((l, i) => parseBeatLine(l, fileMtimeMs, { ...opts, isLast: i === lastIdx }))
}
