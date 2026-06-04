# team-rules/autonomy.md — Ship-it-Autonomie & Definition-of-Blocked (Engine-Canon)

> Wie viel Tempo das Team selbst macht, ohne den `{HUMAN}` für jede Mini-Entscheidung zu stoppen.
> Ergänzt `tiers.md` + `circle-of-trust.md` (die Tier-Matrix sagt **was**, dies hier sagt **wie schnell**).
> Tokens: `{TEAM_LEAD}` = Projekt-Lead, `{HUMAN}` = Product Owner.
> Projekt-Override: gleichnamiges File unter `_dev_team/team-rules/autonomy.md` (Engine = Fallback).

## Ship-it: einmal freigegeben = durchfahren

- **Ein einmal freigegebener Workflow läuft autonom bis Staging durch** — NICHT nach jedem Gate
  erneut um OK fragen. Wurde Schritt 1→2→3 einmal vereinbart, gilt das für alle Wiederholungen
  desselben Workflows. Ständiges Re-Confirm ist Tempo-Killer.
- **Mini-Entscheidungen entscheidet der Owner selbst** (Layout-Detail, Wording, Karte-vs-Timeline)
  nach bestem Wissen. Der `{HUMAN}` schaut sich das **Ergebnis** auf Staging an, nicht 3 Optionen vorab.
- **Melden statt fragen:** Status-Update nach Abschluss („X ist auf Staging, schau's dir an"),
  keine Genehmigungs-Frage vor jedem Schritt.
- **Stoppen nur bei:** (a) Production / DNS / Secrets (T4), (b) irreversibel/teuer, (c) echter
  inhaltlicher Weggabelung, die die `{HUMAN}`-Vision betrifft (nicht: Layout-Detail), (d) ein Gate
  wird **ROT** (echter Blocker).

## Staging-Autonomy

- **`{TEAM_LEAD}` füllt Staging eigenständig**, sobald der volle QM-Circle **ohne Skip GRÜN** ist
  (Review → Compliance → Tests → Release/Pre-Flight, je nach Tier). Kein separates `{HUMAN}`-OK für Staging.
- **Production bleibt `{HUMAN}`-only** — die EINE harte Grenze (T4, maschinell via `deploy-guard`, siehe `tiers.md`).
- Transparenz bleibt: `{TEAM_LEAD}` meldet proaktiv, was deployed wurde. Bei echter Unsicherheit, ob
  der Circle wirklich clean ist → lieber fragen, kein blindes Deployen.

## Definition of Blocked

- **Fehlende *externe* Voraussetzung ≠ Blocker für lokale Arbeit.** Kein Online-Repo / Prod-Server / DNS?
  → lokal scaffolden, bauen, committen; nur der finale **Push** wartet (die 99 % Arbeit läuft trotzdem).
  Production ist ohnehin ein späterer eigener Schritt — die Sorge davor blockiert JETZT nichts.
- **Hakenden Teil parken + melden, nicht den Sprint einfrieren.** Hakt EIN Teil (z. B. ein
  CI-Lockfile), arbeiten die anderen weiter; der hakende Teil wird geparkt + gemeldet.
- **Staging ist die Spielwiese, nicht heilig.** Dort DÜRFEN Fehler passieren — dafür ist es da.
  Mut > Zaudern.
- **Schon-OK = OK.** Was einmal freigegeben war, wird nicht erneut zur Bestätigung vorgelegt. Kein zweites OK.

## Harte Regeln

- Stillstand wegen Nicht-Blockern ist der teuerste Anti-Pattern — er verbrennt Zeit ohne Output.
- Eskalation statt Aktionismus: Unklarheit/Drift → STOP + an `{TEAM_LEAD}`; T4-Bedarf → an `{HUMAN}`.
- T4 ist nie autonom auslösbar — kein Ring, keine Autonomie-Stufe (siehe `tiers.md`, `circle-of-trust.md`).
