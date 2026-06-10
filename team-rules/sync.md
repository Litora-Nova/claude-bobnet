# team-rules/sync.md — State-Sync-Disziplin (beschreibende Regel)

> Diese Datei ist die **Daten-Quelle** für `hooks/session-sync-reminder.sh`. Der Hook rendert
> den Reminder aus dem `REMINDER:`-Block unten + Env (`PROJECT_NAME`, `CANONICAL_BRANCH`,
> `DEV_TEAM_REPOS`). **Reminder-Text ändern = hier editieren, nicht im Script.**
> Projekt-Override: gleichnamiges File unter `_dev_team/team-rules/sync.md` (Engine = Fallback).

## Kanon
- **Sync = Git.** `origin` ist die eine Wahrheit; Maschinen syncen sich über `origin` (push hier → pull dort),
  NICHT direkt Maschine-zu-Maschine.
- Haupt-/Koordinations-Branch: **`$CANONICAL_BRANCH`** (projekt-definiert via Env). Immer wissen, auf welchem Branch man ist.
- **Real (lokal) ↔ VR (remote/LXC) ↔ origin** müssen in sync sein.

## Routinen (Pflicht)
- **Session-Start** — erste Frage „Sync starten?"; bei „go" pro Repo `fetch` → `pull` → `push` + Branch-Check.
- **Stand-up** — Sync (pull + push) als fester erster Schritt vor allem anderen.
- **Feierabend** — ALLES committen (besonders `_dev_team/` + `standup/`, wird chronisch vergessen), dann push.
  Kein offener Working-Tree, kein un-gepushter Commit am Feierabend.

## Harte Regeln
- `git pull` UND `git push` gehören IMMER zum Sync. Lokal committen reicht NICHT.
- Branch-Drift ist die Hauptursache von State-Verlust.
- Vor jeder Extraktion/Copy: `git fetch` + prüfen ob behind origin — NIE eine stale Working-Copy extrahieren.
- **`main`/`master` ist NICHT automatisch der Stand** (PO-Kanon 2026-06-10). Viele Projekte leben
  auf `development`/`staging`/`production` — `main` kann fehlen oder **Jahre** hinter den
  Arbeits-Branches liegen. Beim Boot-Sync in einem vorgefundenen Repo ZUERST prüfen, welche
  Branches existieren und welcher am weitesten vorn ist (`git branch -r` + Ahead-/Datums-Check),
  BEVOR irgendein Branch als kanonischer Stand angenommen wird.

<!-- Der folgende Block wird vom Hook gerendert. Tokens: {PROJECT_NAME} {CANONICAL_BRANCH} {DEV_TEAM_REPOS} -->
REMINDER:
🔄 Sync-Reminder ({PROJECT_NAME}) — Session-Start
  • Bist du auf dem canonical Branch ({CANONICAL_BRANCH})? lokal == origin?
  • Repos syncen (fetch → pull → push): {DEV_TEAM_REPOS}
  • Sync = origin (eine Wahrheit). Nicht stale extrahieren. Branch-Drift = teuerster Fehler.
  • main/master ≠ automatisch der Stand — erst prüfen, welcher Branch vorn ist (development/staging/production?).
  → `bin/sync` macht fetch+pull+push + Branch-Check über alle Repos.
