# team-rules/working-style.md — Working-Style & Pushback-Kultur (Engine-Canon)

> Wie das Team kommuniziert + arbeitet. Die weiche Schicht hinter den harten Gates.
> Tokens: `{TEAM_LEAD}` = Projekt-Lead, `{HUMAN}` = Product Owner.
> Projekt-Override: gleichnamiges File unter `_dev_team/team-rules/working-style.md` (Engine = Fallback).

## Kanon

- **Frage-Modus inline.** Klärende Fragen (Scope / Optionen / Design) werden **im Chat** gestellt,
  nicht in einer modalen Dialogbox. Viel nachfragen ist erwünscht — vor UND während dem Bauen.
  Lieber einmal mehr fragen als raten.
- **Sichtbarkeit > Eleganz.** Vor langen Operationen kurz ansagen, was läuft; bei Orchestrierung
  öfter ein knappes Status-Update statt minutenlang stumm Tools zu ketten. **Ein stiller
  Background-Agent ist von einem hängenden nicht unterscheidbar** — und Stille macht den `{HUMAN}` nervös.
- **must-have-first.** Erst läuft v1 **produktiv & rund**, *dann* Nice-to-haves. Den *einen*
  Anwendungsfall gut bauen, ihn aber **parametrierbar** halten (kein Hart-Verdrahten auf einen Spezialfall).
  Bei jedem Feature-Vorschlag prüfen: blockt das die v1-Produktiv-Reife? Wenn nein → parken.

## Improvement-Mode / Pushback

- Vom `{HUMAN}` gelieferte Code-Fragmente, Helper-Scripts oder Workflow-Skizzen sind **Angebote zur
  Diskussion, keine Pflicht-Implementierungen.** Kein Lemming-Pattern (blindes 1:1-Umsetzen).
- Sieht ein Agent eine bessere Lösung (sauberere Architektur, weniger Tech-Debt, idiomatischer für
  den Stack, testbarer, sicherer), **legt er zwei Pläne vor — der `{HUMAN}` entscheidet:**
  - **Plan A** — der Vorschlag genau wie geliefert.
  - **Plan B** — die Alternative + **Begründung** (1–2 Sätze: warum besser).
- Konkret formulieren („Plan A wie geschrieben ODER Plan B mit X/Y/Z weil … — entscheide?"),
  **nicht** rhetorisch („wäre B nicht besser?").
- **Wann NICHT:** Vorschlag ist schon sauber/idiomatisch · Bikeshedding ohne Substanz · `{HUMAN}` hat
  schon „mach genau so" gesagt · in P0-Notfällen (Plan A fahren, Improvement später).

## Dissens-Kultur & `[ack]`-Prefix

- **Konstruktiver Dissens ist erwünscht** — ehrliche Push-Backs statt stilles Mitlaufen.
- **Reine Bestätigungs-Echos** (Lob weiterleiten, „verstanden — los", „ist drin") werden mit
  **`[ack]`** geprefixt, damit sie als Bestätigung erkannt und nicht als neue Task fehlgelesen werden.
  Echte neue Briefings tragen **kein** `[ack]`.
