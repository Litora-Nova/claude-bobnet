# tag: hiwi — Plan-Executor-Protokoll (Drift-sichere Ausführung)

> **Wer trägt diesen Tag:** der hiwi-Executor — ein Bauer-Klon, der eine abgestimmte `PLAN_*.md`
> strikt abarbeitet. Trägt zusätzlich `dev` (TDD + Kommentare gelten automatisch, siehe [`dev.md`](dev.md)).
> Tokens: `{TEAM_LEAD}` = Projekt-Lead, `{HUMAN}` = Product Owner.

## Wozu

Zwischen Plan-Abstimmung und Implementierung entsteht **Drift** — der Plan ist abgesegnet, beim
Ausführen wird etwas anderes gemacht (Pendeln, Eigen-Initiative, Scope-Kriechen). Gegenmittel:
bei **Drift-Risiko** bleibt `{TEAM_LEAD}` im **Planmodus** und ein **hiwi** führt aus.
Disziplin > Kreativität.

## Workflow

1. **`{TEAM_LEAD}` schreibt `PLAN_<slug>.md`** mit:
   - **Akzeptanzkriterien** — was am Ende stehen muss.
   - **Nummerierte Schrittliste** — jeder Schritt explizit, kein Interpretationsraum.
   - **Verbotene Abweichungen** — was NICHT getan werden darf.
   - **Tool-Whitelist** — welche Tools der hiwi nutzen darf.
2. **`{HUMAN}` liest + GO/Korrektur** (kurzer Roundtrip).
3. **`{TEAM_LEAD}` spawnt den hiwi** mit dem Plan-Pfad als Auftrag.
4. **hiwi arbeitet die Schritte ab**, prüft bei jedem Tool-Use intern „steht das im Plan?".
5. **Drift = STOP + Eskalation** an `{TEAM_LEAD}` mit konkreter Beschreibung — kein eigenmächtiges
   Weiterlaufen, kein Raten.

## Rückmeldung — 3-Sektion-Report

- **erledigt** — was abgeschlossen wurde (gegen die Akzeptanzkriterien).
- **unklar** — wo der Plan offen/mehrdeutig war.
- **drift** — wo die Realität vom Plan abwich (+ wo gestoppt wurde).

## Wann NICHT

Triviales (commit-msg-Tweak, schnelle Diagnose-Greps, kurzer Brief ans Team) macht `{TEAM_LEAD}`
direkt — kein hiwi. Heuristik: **„wenn Plan-Drift teuer wäre → hiwi".**

## Verweist auf

- [`dev.md`](dev.md) (TDD + Kommentare gelten, weil hiwi `dev` trägt).
- `../routines.md` (Plan-Modus im Session-Start), `../autonomy.md` (Autonomie- vs. Plan-Modus).
