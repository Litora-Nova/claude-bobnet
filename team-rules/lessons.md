# team-rules/lessons.md — Lessons that pay off (Engine-Canon)

> Generischer Reflex-Katalog: teure Fehler, die sich wiederholen, als knappe Heuristiken.
> Kein Projekt-Wissen — nur Muster, die in jedem Team-OS gelten.
> Tokens: `{TEAM_LEAD}` = Projekt-Lead, `{HUMAN}` = Product Owner.
> Projekt-Override: gleichnamiges File unter `_dev_team/team-rules/lessons.md` (Engine = Fallback).

## Stale-Instanz vor Code-Bug

- **Ein nicht-reproduzierbarer „Bug" ist fast immer eine stale laufende Instanz, kein Code-Fehler.**
  Bei mehreren parallelen Dev-Servern (Agents + `{HUMAN}`-Terminal) hinkt die laufende Instanz dem
  Code leicht hinterher.
- **Reflex:** Symptom lässt sich gegen den *aktuellen* Code lokal nicht reproduzieren → zuerst die
  laufende Instanz verdächtigen. **Empirisch gegen den aktuellen Code prüfen** (echter Request +
  Daten-Check, Logik-Runner) **bevor** man einen Fix jagt. Eine stale Frontend-Instanz NIE
  durchklicken — sie ist irreführend; der saubere Beweis gehört auf den frischen Deploy/Staging.

## Tooling vor Eigenbau

- **Keinen Mechanismus nachbauen, den vorhandene Tooling schon kann.** Erst prüfen, ob ein
  Gem/Recipe/Modul/App-Script es bereits leistet.
- **Blocker an der Quelle fixen** (das fehlende Paket bauen / paketieren) oder warten — **kein
  Parallel-Hack** als Workaround.
- **Deploy / Infra gehört in die *besitzende* App**, nie in eine fremde verlegt.
- **Konzept-Fit vor dem Bauen:** das Gate fragt bei jedem neuen Deploy-/Infra-Baustein „passt das ins
  bestehende Konzept, oder erfinden/verlegen wir was?" — und holt `{HUMAN}`-Sign-off VOR dem Bauen.
