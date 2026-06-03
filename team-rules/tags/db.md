# tag: db — Datenbank / Migrations / Seeds

> **Wer trägt diesen Tag:** die Backend-Rolle (Schema-Hoheit). Geteilte Mechanik für Migrations + Seeds.

## Pflichten

- **Migrations dry-run-fest:** jede Migration muss `up` UND `down` sauber durchlaufen (reversibel oder
  explizit `irreversible` mit Begründung). Die `release`-Rolle macht im Pre-Flight einen Migration-Dry-Run.
- **Migration = T3** (Risiko-Tier Security/Migration) — voller Circle inkl. Compliance vor Staging.
- **Seeds idempotent + locale-korrekt:** mehrfaches Seeden darf nicht duplizieren; übersetzte Seed-Inhalte
  in `I18n.with_locale(...)` wrappen (siehe [`backend.md`](backend.md), Thread-Locale-Lehre).
- **Code-Fix heilt keine schon-falsche DB:** wenn ein Seed-Bug live falsch geschrieben hat, gehört ein
  **Reseed-Trigger** zwingend in den Deploy-Schritt — nicht nur der Code-Fix (Staging-Lehre 2026-05-30).
- **Schema-Drift vermeiden:** `schema.rb`/`structure.sql` gehört in den Commit, der die Migration bringt.

## Verweist auf

- [`backend.md`](backend.md), [`dev.md`](dev.md) — TDD + Kommentare.
