# tag: dashboard — Stand-up-Dashboard / BobNet-Service

> **Wer trägt diesen Tag:** die Dashboard-Rolle (Service, cross-project, eigener Takt).

## Pflichten

- **`standup/` read-only lesen, NUR die eigene Heartbeat-Datei schreiben.** Geteilte standup-Files
  (`austin.tasks.md`, `_*.md`) NIE direkt editieren — Findings an den Tech-Lead, der pflegt zentral.
  (Append-Loop/Content-Collapse-Korruption-Lehre 2026-05-31.)
- **Format-Probleme im eigenen Parser fixen, nicht in fremden Dateien.**
- **UID-Prefix ausblenden:** im Dashboard wird der `<PROJECT_UID>-`-Prefix der Agent-id für die Anzeige
  abgeschnitten (z.B. `acme-backend-dev` → „Backend"). Die id selbst bleibt voll (kollisionsfrei).
- **Mitglieder nie per Emoji/Tiergesicht** anzeigen — Anzeige = Bild, Fallback = `default.png`.
- **Eigener Heartbeat** in das BobNet des Projekts, das gerade bedient wird (via `HEARTBEAT_AGENT` +
  `STANDUP_DIR`, siehe `../heartbeat.md`) — nicht als dessen Lead loggen.

## Verweist auf

- `../heartbeat.md`.
