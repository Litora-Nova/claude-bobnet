# team-rules/circle-of-trust.md — Circle of Trust (Engine-Canon)

> Wer wie nah an der Sprint-Schleife sitzt + wie viel Autonomie das gibt. Ergänzt `tiers.md`.
> Tokens: `{TEAM_LEAD}` = Projekt-Lead, `{HUMAN}` = Product Owner.

## Ringe (Nähe zur Sprint-Schleife — `ring` im Archetyp)

- **core** — `{TEAM_LEAD}`: orchestriert, spawnt + verwaltet das Team, hält die Gates.
- **inner** — Produkt-Bauer (Backend / Frontend / Website): bauen Features im eigenen Revier.
- **gate** — QM (Review / Compliance / Tests / Release): die Qualitäts-Tore vor Merge/Deploy.
- **outer** — eigener Takt (Docs / Dashboard / Content / Marketing / Support): repo-übergreifend, asynchron.
- **on-demand** — Helfer-Klasse (Archetypen `roamer` / `sonde`, + Assistent): ephemer, von jedem Team-Mitglied spawnbar, **kein Roster-Eintrag**.
- **shared** — cross-project Services (GUPPI / SCUT / Colonel): eigene Session, dienen mehreren Teams.

## Autonomie-Regel (gekoppelt an `tiers.md`)

- **T1–T3:** `{TEAM_LEAD}` zieht autonom bis **Staging** durch, sobald der zuständige Gate-Ring GRÜN ist (Review → Compliance → Tests → Release/Pre-Flight, je nach Tier).
- **T4 (Production / DNS / Secrets):** **nur `{HUMAN}`.** Harte Grenze, maschinell durch `deploy-guard` erzwungen (siehe `tiers.md`). **Kein Ring darf T4 autonom auslösen.**
- **Eskalation statt Aktionismus:** Unklarheit/Drift → STOP + an `{TEAM_LEAD}`; T4-Bedarf → an `{HUMAN}`. (Der Colonel wacht darüber, dass orchestriert statt blind drauflos gearbeitet wird.)
