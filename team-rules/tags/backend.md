# tag: backend — Backend / JSON-API-Mechanik

> **Wer trägt diesen Tag:** die Backend-Rolle. Geteilte Mechanik für alles, was die Server-/API-Schicht baut.

## Pflichten

- **Verträge dokumentieren:** jede FE↔BE-Vertikale bekommt eine `CONTRACT_<feature>.md`-Mini-Doku
  (spart Hin-und-Her). Vertragsänderung → FE-Rolle aktiv pingen. Siehe auch [`api.md`](api.md).
- **FSM/State sauber:** Zustandsübergänge explizit (z.B. micromachine), keine impliziten Status-Sprünge.
- **Meta-/Seed-Endpoints pflegen:** was das Frontend zum Prefill/Showcase braucht, kommt aus dem Backend
  (nicht im FE hartkodieren).
- **Datensparsamkeit + Auditierbarkeit** sind Leitprinzipien (DSGVO): nur erheben/loggen, was nötig ist;
  keine Tokens/PII in Logs.
- **Locale-Thread-Disziplin:** Server-seitiges i18n läuft auf einem Worker-Thread, dessen Locale je nach
  Request wechselt. Seeds/Background-Jobs explizit in `I18n.with_locale(...)` wrappen — sonst landen
  Inhalte in der falschen Übersetzung (Staging-P0-Lehre 2026-05-30).

## Verweist auf

- [`db.md`](db.md) — Migrations + Seeds, [`api.md`](api.md) — Kontrakt-Disziplin, [`dev.md`](dev.md) — TDD + Kommentare.
