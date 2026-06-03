# tag: website — Marketing-Sites (statische Generierung)

> **Wer trägt diesen Tag:** die Website-Rolle. Geteilte Mechanik für die öffentlichen Marketing-Sites.

## Pflichten

- **SEO-Basics pro Page Pflicht** vor „done": `<title>`, `<meta name="description">`, `useSeo`/`useHead`-Setup
  pro Page, locale-aware. Details in [`seo.md`](seo.md).
- **URL ↔ Locale-Konsistenz:** ist EN Default, sind `/` + alle non-de-URLs englisch (`/contact`, `/imprint`
  statt `/kontakt`, `/impressum`). Page-Filenames pro Locale via i18n-`pages`-Mapping (Mechanik, kein Judgement).
- **i18n-Parität:** alle Strings in beiden Locales, kein Hardcode ohne `$t()`-Key. Siehe [`i18n.md`](i18n.md).
- **Keine toten Links/Buttons** (wie Frontend).
- **Asset-Disziplin:** Bilder optimiert (OG ≤300KB, sinnvolle Auflösung), Cache-Headers für static Assets
  geprüft (sonst lädt es online ewig). Asset-Pipeline-Änderung → in den Pre-Flight.
- **Kein CMS, kein Tracking** (Datensparsamkeit).

## Verweist auf

- [`js.md`](js.md), [`seo.md`](seo.md), [`i18n.md`](i18n.md), [`dev.md`](dev.md).
