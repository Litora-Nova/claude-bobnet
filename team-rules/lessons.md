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

## Multiplexer-Automatisierung (Agent steuert fremde Panes — tmux | zellij)

- **Engine ist multiplexer-agnostisch (tmux|zellij) über `scripts/lib/mux.sh`.** NIE direkt
  `tmux` oder `zellij` aufrufen — immer die `mux_*`-Verben (`mux_spawn/has/list/send/capture/kill`).
  Eine Stelle entscheidet das Backend (`BOBNET_MUX=tmux|zellij|auto`, Default auto = tmux-bevorzugt);
  Direktaufrufe brechen auf dem jeweils anderen Backend und unterlaufen die Rückwärtskompat.
- **zellij-send/capture wirkt NUR auf Sessions mit angebundenem Client.** `action write-chars` /
  `action dump-screen` gegen rein **detached** Sessions sind best-effort — stiller Reinfall, kein
  Fehler. Deshalb ist Inter-Bob-Comms ohnehin Inbox-first (`comms.md`); der Injection-Pfad bleibt
  Notfall. (tmux hat diese Grenze nicht — wer sich darauf verlässt, scheitert beim Backend-Flip.)
- **Sessions exakt adressieren** (tmux `session:window`/`=name`, zellij `--session NAME`): stirbt
  die Ziel-Session, fällt Präfix-Matching still auf die nächstähnliche um — im schlimmsten Fall
  tippt man in die eigene.
- **`pkill -f <muster>` killt die eigene Shell**, wenn das Muster in der eigenen Kommandozeile
  steht (und das tut es beim Aufräumen fast immer). Muster splitten (`'foo''bar'`) oder per PID killen.
- **Vor jedem Send in eine interaktive Session: Prompt-Zustand capturen** (`mux_capture`). Ein
  „leerer" Prompt kann ein Non-Breaking-Space (`c2 a0`) tragen — byte-genau vergleichen statt
  `grep '^❯ *$'`. Steht fremder ungesendeter Text im Buffer: NIE reinsenden, warten oder anderen
  Kanal nehmen. **Capture und Send NIE im selben Befehl; Text und Enter SEPARAT.**

## Parallele Hintergrund-Agenten im geteilten Working-Tree

- **Zwei *bauende* Agenten (die `git checkout`/`commit`) gleichzeitig im SELBEN Working-Tree =
  Kollision.** Ein `checkout -b` des einen schaltet den Tree unter dem anderen um → verlorene/
  fehlgeleitete Commits. Empirisch passiert; die Agenten fingen es ab, aber Glückssache.
- **Reflex:** parallele Builder → jeder einen **eigenen git-Worktree** (`isolation: "worktree"`)
  ODER **sequenzieren**. Reviere (Dateien) trennen reicht NICHT — der eine Tree ist der Konflikt.
- **Read-only Gate-Agenten** (Review/Compliance, ref-basierte Diffs, kein checkout) sind dagegen
  **safe-parallel** — sie mutieren den Tree nicht. Die Unterscheidung Builder-vs-read-only ist der Schlüssel.

## Lokale Task-IDs ≠ Issue-Nummern in Commit-Messages

- **Eine Task-/Backlog-Nummer im Kopf ist NICHT die Issue-Nummer im Tracker.** Wer eine lokale
  Task-Nummer als `#N` in eine Commit-Message schreibt, ohne dass `#N` das gemeinte Tracker-Issue
  ist, erzeugt auf dem (öffentlichen) Repo eine Cross-Referenz auf ein FREMDES Issue — und
  History-Rewrite zum Fixen ist meist tabu. (Dieser Absatz nutzt bewusst nur `#N` in Backticks.)
- **Reflex:** Bevor `#N` in eine Commit-/PR-Message kommt — entweder das Issue ZUERST anlegen und
  die echte Nummer nehmen, oder `#N` weglassen. Lokale Orchestrierungs-Tasks ≠ Tracker-Issues.
