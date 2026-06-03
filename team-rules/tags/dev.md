# tag: dev — Bauer-Pflichten (TDD + Kommentare)

> **Wer trägt diesen Tag:** jede Rolle, die Produkt-Code baut (backend, frontend, website, content, hiwi).
> Trägt eine Rolle `dev`, gelten die folgenden Pflichten **automatisch** — das ist die Mechanik hinter
> der Plan-Regel „TDD (wenn dev) · Kommentare schreiben (wenn dev)".

## TDD ist Pflicht, nicht optional

- **Test ZUERST** bei neuen Features (TDD-Reflex), nicht erst-bauen-dann-verifizieren.
- **Jeder Logik-Pfad braucht eine Spec.** Kein „später" — fehlt eine Spec für einen neuen Code-Pfad,
  pingt die `tests`-Rolle VOR dem Merge (kein stiller Durchlass).
- **Behavior > Pattern:** ein Test prüft beobachtbares I/O-Verhalten (Input→Output, DB-State,
  Render-Outcome, Network-Count), nicht nur dass ein Source-String existiert. Reine Source-Pattern-Specs
  bekommen vom Review GELB.
- **UI-Bugs → echter Browser** (Playwright/E2E). curl/headless reicht nicht für Render-/Layout-/Locale-Bugs.
- **Coverage-Floor in CI** halten; neue Pfade dürfen ihn nicht senken.

## Kommentare schreiben

- **Root-Cause dokumentieren:** bei Bug-Fixes WARUM (nicht nur was) — wann/warum der Bug entstand,
  wo der Regressions-Anker liegt (die Phase-D-Commits sind das Vorbild).
- **Keine Wegwerf-Kommentare** (`// TODO`, auskommentierter Code, `console.log`/`puts`-Debug-Reste) im
  Merge — das Review flaggt sie als House-Rule-Verstoß.
- **Pure Logik dokumentiert ihre Verträge** (Parameter, Rückgabe, Invarianten) — gerade wenn sie aus
  einer Komponente herausgezogen wurde.

## Immer Docs (House-Rule)

Wer ein un-dokumentiertes System übernimmt + scannt: Erkenntnisse fließen in die entstehende Doku.
Wichtige/auditrelevante Dinge werden dokumentiert. Details: [`docs.md`](docs.md).
