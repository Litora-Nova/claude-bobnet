// PO-Tasks-Datei-Auflösung — PURE function, bewusst .mjs (kein TS): direkt per
// node testbar (tests/dashboard_po_tasks_file_spec.sh), nitro importiert mjs problemlos.
//
// White-Label-Rename (PO-Wunsch): die Engine-Default-Konvention ist `po.tasks.md`
// (kein Klarname mehr). BESTANDSINSTANZEN nutzen aber weiter ihre echte
// `austin.tasks.md` (Legacy) — diese darf NICHT verwaisen. Darum eine
// Vorrang-Kette statt eines harten Renames:
//
//   1. `po.tasks.md` existiert      → die nehmen (neue/migrierte Instanz)
//   2. sonst `austin.tasks.md` da   → die nehmen (Legacy-Instanz: read UND write,
//                                      damit das Tasks-/Briefing-Panel nicht leer
//                                      läuft und nichts verwaist)
//   3. sonst                        → Default `po.tasks.md` (neu anlegen)
//
// So bleibt jede Bestandsinstanz voll funktionsfähig, neue Instanzen sind sauber
// white-label, und es entsteht nie eine zweite, doppelte Tasks-Datei.
import { existsSync } from 'node:fs'
import { join } from 'node:path'

export const PO_TASKS = 'po.tasks.md'
export const LEGACY_PO_TASKS = 'austin.tasks.md'

// Liefert den ABSOLUTEN Pfad der zu nutzenden Tasks-Datei in `dir`.
// Reine Existenz-Heuristik (synchron, kein I/O-Inhalt) → trivial node-testbar.
export function tasksFile(dir) {
  if (existsSync(join(dir, PO_TASKS))) return join(dir, PO_TASKS)
  if (existsSync(join(dir, LEGACY_PO_TASKS))) return join(dir, LEGACY_PO_TASKS)
  return join(dir, PO_TASKS)
}
