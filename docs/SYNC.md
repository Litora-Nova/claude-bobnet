# State-Sync-Disziplin (claude-bobnet)

**State sauber halten ist Pflicht.** Drift zwischen lokal (z. B. Mac/Real-Instanz) und remote
(LXC/VR-Instanz/origin) ist der teuerste Fehler — er kostet Tasks und Arbeit auf veralteter Basis.
(Lehre 2026-06-02: nie gepullt + falscher Branch → Tasks fehlten lokal + veraltete Version extrahiert.)

## Canonical
- Haupt-/Koordinations-Branch: **`claude`** (bzw. projekt-definiert). IMMER wissen, auf welchem Branch man ist.
- **Real (lokal) ↔ VR (remote/LXC) ↔ origin** müssen in sync sein. Mac↔LXC ist eine Pflicht-Achse.

## Routinen (Pflicht)
### Session-Start — ERSTE Frage: „Sync starten?"
Bei „go": pro Repo `git fetch` → `pull` → `push`; **Branch-Check** (richtiger/canonical Branch? lokal == remote == origin?).

### Stand-up
Sync (pull + push) als **fester erster Schritt** vor allem anderen.

### Feierabend
**ALLES committen** — besonders `_dev_team/` + `standup/` (wird chronisch vergessen) — dann push.
**Kein offener Working-Tree am Feierabend.**

## Harte Regeln
- `git pull` gehört **IMMER** zum Sync. Branch-Drift ist die Hauptursache von State-Verlust.
- **Vor jeder Extraktion/Copy eines Repos:** `git fetch` + prüfen ob behind origin — NIE eine stale Working-Copy extrahieren.
- `_dev_team/` (committed) ist der **State-Kanon**; Symlinks zeigen aus `~/.claude` darauf (`bin/onboard`).
- **Secrets** (`.secrets/`) NIE committen — out-of-band (scp/Syncthing).

## Tooling (geplant — Phase 4)
- `bin/sync` — ein Befehl: fetch+pull+push über alle registrierten Repos + Branch/Drift-Report.
- Hook: `SessionStart` erinnert an Sync / triggert `bin/sync`.
- Remote (LXC) committet seinen State selbst (VR-Bob Feierabend) statt dass die Real-Instanz remote schreibt.
