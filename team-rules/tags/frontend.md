# tag: frontend — App-Frontend-Mechanik (SPA / App)

> **Wer trägt diesen Tag:** die Frontend-Rolle. Geteilte Mechanik für Components, Pages, Composables, API-Clients.

## Pflichten

- **Title-Spec pro Page:** jede Page hat einen Test, der `<title>` rendert — in **beiden Locales**.
- **Composables → Unit-Tests:** `useApi`/`useAuth`/`useSeo`/… bekommen Happy-Path + ≥1 Edge-Case.
- **Pure Logik aus Components herausziehen + testen:** Render-Logik in eine testbare Funktion/Composable,
  Component wird schlankes Template-Wiring (leichter zu testen, kein fragiler Mount).
- **Keine toten Links/Buttons:** jeder CTA/Button/Link führt zu einer existierenden Page, setzt einen
  Scroll-Anker, oder triggert eine echte Action. „Kommt-später"-Buttons → RAUS oder Diskussions-Task an den PO.
- **Vertrag konsumieren, nicht erfinden:** API-Shapes kommen aus `CONTRACT_<feature>.md` (Backend-Owner),
  nicht aus dem Frontend geraten — siehe [`api.md`](api.md).

## Verweist auf

- [`js.md`](js.md), [`i18n.md`](i18n.md), [`api.md`](api.md), [`dev.md`](dev.md).
