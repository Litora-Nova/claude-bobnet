# tag: seo — SEO-Basics (öffentliche Pages)

> **Wer trägt diesen Tag:** die Website-Rolle (öffentliche Marketing-Pages). Querschnitt — Review prüft beim Tick.

## Pflichten

- **Pro public Page Pflicht vor „done":** `<title>`, `<meta name="description">`, `useSeo`/`useHead`-Setup —
  locale-aware. (Beim Apple-Slate-Re-Skin verschwand das komplett, niemand merkte es — Lehre: explizit verifizieren.)
- **`useSeo`-Composable für jede public Page** nutzen (zentral, locale-aware), nicht pro Page hand-rollen.
- **OG-Bilder:** vorhanden, optimiert (≤300KB, 1200×630), Pfade stabil. Master-Originale als Source-of-Truth sichern.
- **Verify-Mechanik:** der Live-Verify greppt nach `<title>` pro Page; das Review prüft, dass `useSeo`/`useHead`
  aufgerufen wird. SEO ist ein häufiger Test-Gap (JSDom kann's nur teilweise) → im Pre-Flight explizit mitprüfen.

## Verweist auf

- [`website.md`](website.md), [`i18n.md`](i18n.md), [`dev.md`](dev.md).
