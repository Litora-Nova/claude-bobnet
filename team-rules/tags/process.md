# tag: process — Prozess-Audit (Disziplin-Wächter)

> **Wer trägt diesen Tag:** die Process-Auditor-Rolle (Colonel). Meta-Kontrolle, abgegrenzt von `compliance`
> (die prüft Code/Deps, nicht den Prozess). Scheduled / GUPPI-getriggert.

## Pflichten

- **Gate-Lauf-Nachweis pro Sprint einfordern:** liefen review → compliance → tests → release wirklich,
  oder wurden sie umgangen weil ein Sprint „klein und schnell" wirkte? (Genau der Anti-Pattern, der
  Production-Bugs durchließ.)
- **Push-Policy-Verstöße flaggen:** Push nur auf erlaubte Branches, NIE direkt auf den Default-Branch.
- **Heartbeat-Frische** prüfen: sind die Agents wirklich aktiv, oder läuft etwas tot?
- **Sync-Disziplin** prüfen: fetch → pull → push gegen `origin`, Branch-Check (auf dem Canonical-Branch?
  HEAD == origin?).
- **Lead orchestriert statt Aktionismus:** ist der Tech-Lead im Koordinations-Modus, oder baut er selbst,
  was ein Worker tun sollte?
- **Eskaliert Prozess-Drift an Tech-Lead + PO** (kein Code-Touch).

## Verweist auf

- `../tiers.md`, `../sync.md`, `../heartbeat.md`.
