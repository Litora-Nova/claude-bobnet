# tag: design — Design-Doktrin (Component-first + Leitplanken)

> **Wer trägt diesen Tag:** jede Rolle, die HTML-Mockups und UI-Design-Vorlagen liefert.
> Trägt eine Rolle `design`, gelten die folgenden Pflichten **automatisch**.

## Component-first (wichtigster Arbeitsgrundsatz)

**Baue Mockups durch KOMPONIEREN, nicht durch Neubau.** Header, Footer, Sidebar, Tokens,
Icons leben **einmal** in einer geteilten `_shared/`-Lib. Ein neues Mockup bindet sie ein
und liefert nur seinen **einzigartigen Inhalt**.

**Selbst-Check vor jedem Bau:** „Schreibe ich gerade Header/Footer/Sidebar/Tokens neu?" → **Stopp.**
Nutze oder erweitere die bestehende Komponente. Änderungen an geteilten Elementen (z.B. neuer
Sidebar-Punkt, neuer Header-State) gehen in die **geteilte Komponente** — dann erben
**alle** Mockups die Änderung automatisch. Single-Source-of-Truth: 1× ändern → alle Mockups erben.

### Empfohlene `_shared/`-Struktur
```
_shared/
  tokens.css        // alle Farb-/Radius-/Font-Variablen je Theme (Tenant umschaltbar)
  base.css          // Reset, Buttons, Cards, Tabelle, Badges, Inputs — generisch
  icons.js          // Icon-Pathmap + Render-Helfer
  ui.js             // Render-Funktionen der geteilten Komponenten
  README.md         // Kurz-Doku aller Komponenten + Props
```

### Header/Footer-Varianten
- **`Header(variant)`**: Zustände `guest` / `user` / `admin` (+ Sprache, Login/Avatar, CTA je State).
- **`Footer(variant)`**: z.B. `full` / `slim`.
- Neue Variante = Erweiterung der geteilten Komponente, kein neues File.

### Logo
Ein inline-SVG-Komponenten-File pro Typ (`currentColor` + CSS-Vars, App-Level). Nie als Bild-Asset hartcodieren.

### Bild-Assets (Illustrationen / Heros)
Raster-Bilder NICHT von Hand: **`scripts/image-gen.sh "<prompt>" [out.jpg]`** (shared Tool, Cloudflare Workers AI) — parametrische Prompts, gemeinsames Style-Template. Logos/Icons bleiben Vektor (siehe Logo).

---

## Design-Leitplanken (HART)

- **Farben als CSS-Variablen** (in `tokens.css`) → Theme/Tenant umschaltbar.
  Niemals Farbwerte hart im HTML/JS streuen. Neuer Tenant = nur neue Token-Overrides in `tokens.css`.
- **KEINE Emojis im UI** → **mdi-Icons** (Inline-SVG, `currentColor`). Nie Emoji-Codepoints `>=0x1F000` oder `0x2600–0x27BF`.
- **Vuetify-nativ denken**: Mockup-Komponentennamen spiegeln echte Vuetify-Komponenten
  (`TheHeader`, `TheFooter`, `AdminShell`, `DataTableToolbar` …). Mockup-Reuse = App-Reuse.
  Keine Inline-`style=`-Layouts wo Komponenten gehören.
- **Immer Desktop UND Mobil.** Mobil = kompakter, gleiche Inhalte (einspaltig, enger).
- **Zustände zeigen:** leer, gefüllt, ladend, Fehler, „nicht verfügbar" — wo sinnvoll mit Demo-Umschalter.
- **Bei Explorations-Aufgaben:** 1–2 Optionen + kurze Empfehlung mit Begründung — keine stillen
  Visual-Entscheidungen; Richtungswahl liegt beim PO.

---

## Quality-Gate (vor JEDER Lieferung)

1. **JS gültig:** `node --check` über alle `<script>`-Blöcke und `_shared/*.js`.
2. **Tag-Balance:** `<div>`-Öffner == `</div>`-Schließer (auch `<section>`).
3. **Kein Emoji im UI:** Scan auf Codepoints `>=0x1F000` oder `0x2600–0x27BF`.
4. **Referenzen prüfen:** `_shared/*`-Includes vorhanden; Mockup rendert ohne Konsole-Fehler.
5. **Visuelle Selbst-Verifikation:** Playwright-Screenshot aufnehmen und ansehen — Layout,
   Farben, Mobile-Breakpoint, Zustände kurz prüfen, bevor das Mockup als erledigt gilt.
