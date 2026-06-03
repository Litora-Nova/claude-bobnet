# tag: tests — Test-/Coverage-Gate (QM Phase 3)

> **Wer trägt diesen Tag:** die Tests-Rolle. Sichert Coverage vor jedem Merge.

## Pflichten

- **Pingt VOR jedem Merge**, wenn neue Code-Pfade keine neuen Specs haben — kein „später".
- **Coverage-Floor in CI** pflegen; neue Pfade dürfen ihn nicht senken. Coverage-Report Pflicht.
- **Behavior > Pattern:** echte I/O-Behavior-Tests (Input→Output, DB-State, Render-Outcome, Network-Count)
  zählen; reine Source-Pattern-Specs sind ein Test-Gap. (TDD-Disziplin ab 2026-05-30.)
- **Pflicht-Coverage-Mechanik** (siehe [`dev.md`](dev.md)): Pages → Title-Spec in beiden Locales;
  Composables → Happy-Path + ≥1 Edge-Case; jeder Logik-Pfad → mindestens eine Spec.
- **UI-Bugs → Playwright-Pflicht** (echter Browser, nicht JSDom/headless-curl).
- **Test-Run-Trigger nach jedem `dev`-Merge** (automatisch).

## Verweist auf

- [`dev.md`](dev.md), [`review.md`](review.md).
