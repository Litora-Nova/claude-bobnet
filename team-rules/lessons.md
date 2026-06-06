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

## Hängende Browser-/Paket-Downloads (Playwright & Co.)

- **Ein Install, der reproduzierbar an derselben Stelle hängt (0 CPU, 0 offene Sockets), ist ein
  CDN-/Routen-Problem — kein „nochmal probieren".** Diagnose: Prozess-CPU + `ss -tnp` + Zielordner-
  Größe über 2 Minuten beobachten; konstant = tot.
- **Reflex Playwright:** der `--dry-run` des Installers (`node cli.js install <browser> --dry-run`)
  druckt die ECHTEN Download-URLs + Zielpfade — erst lesen, dann handeln. Ist die Primär-Route
  kaputt, die Alternativ-Route (z. B. `builds/cft/…`) per `curl -C - `-Resume-Schleife laden,
  ins erwartete Cache-Verzeichnis entpacken und die Marker-Dateien (`INSTALLATION_COMPLETE`,
  `DEPENDENCIES_VALIDATED`) setzen. Torso + `__dirlock` vorher löschen.
- **`unzip -tq` vor dem Entpacken** — ein „fertiger" Download kann ein 24-Byte-Fehlerdokument sein.

## tmux-Automatisierung (Agent steuert fremde Panes)

- **Sessions exakt adressieren** (`session:window` oder `=name`): stirbt die Ziel-Session, fällt
  Präfix-Matching still auf die nächstähnliche um — im schlimmsten Fall tippt man in die eigene.
- **`pkill -f <muster>` killt die eigene Shell**, wenn das Muster in der eigenen Kommandozeile
  steht (und das tut es beim Aufräumen fast immer). Muster splitten (`'foo''bar'`) oder per PID killen.
- **Vor jedem `send-keys` in eine interaktive Session: Prompt-Zustand capturen.** Ein „leerer"
  Prompt kann ein Non-Breaking-Space (`c2 a0`) tragen — byte-genau vergleichen statt `grep '^❯ *$'`.
  Steht fremder ungesendeter Text im Buffer: NIE reinsenden, warten oder anderen Kanal nehmen.
