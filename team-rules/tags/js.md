# tag: js — JavaScript / TypeScript / Nuxt-Mechanik

> **Wer trägt diesen Tag:** frontend + website (Nuxt/Vue-Stack). Geteilte Mechanik für die JS-Schicht.

## Pflichten

- **Layer vs. App-Branding trennen:** Brand/Theme/Palette gehören auf App-/Company-Level (in die App),
  NIE in einen geteilten Layer (der dient mehreren Apps). Layer = nur generische Mechanik.
- **SSR-Kompatibilität:** keine handgerollten Plugin-Hacks, die SSR brechen — offizielle Module bevorzugen
  (Vuetify-SSR-Lehre: offizielles `vuetify-nuxt-module` statt handgerolltem `vite-plugin-vuetify`).
- **Stale-Build vor Code-Bug verdächtigen:** ein nicht-reproduzierbarer „Bug" ist oft eine stale Dev-Instanz —
  gegen aktuellen Code empirisch prüfen (frischer Build/Restart) bevor man Code-Bugs jagt.
- **Kompakte Component-Tags:** HTML/Vue-Tags möglichst einzeilig, Attribute nicht über viele Zeilen brechen.
- **Lockfile-Touch pingt Compliance** automatisch (Standing-Order) — siehe [`compliance.md`](compliance.md).

## Verweist auf

- [`dev.md`](dev.md), [`i18n.md`](i18n.md).
