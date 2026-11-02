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

- **Kanon (PO-Entscheid 2026-07-17, #64): tmux ist der Fleet-Default für headless Betrieb,
  zellij ist für headless deprecatet** (interaktive Sessions bleiben mit zellij unterstützt).
  Auslöser: der zellij-Draft-Befund direkt unten war kein Rand-Fall, sondern der Grund für die
  gesamte 0.14.0-Watcher-Härtung (Draft-Flush, Heartbeat-Verifikation statt rc, Re-Nudges,
  Eskalation) — plus lingernde Session-Leichen nach Kill/Boot-Zyklen und spürbare
  Verlangsamung bei vielen Sessions (Flotten-Maßstab). Neue/rollende Installationen setzen
  `BOBNET_MUX=tmux` explizit, statt sich auf `auto` zu verlassen.
- **Engine bleibt multiplexer-agnostisch (tmux|zellij) über `scripts/lib/mux.sh`.** NIE direkt
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

## Release-Artefakte: Identität im Quell-Commit binden

- **Ein Installer, der Binary und Prüfsumme aus demselben veränderbaren Release lädt, prüft nur
  den Transport, nicht die Identität.** Wer beide Assets ersetzt, ändert die ausgeführten Bytes,
  während der geprüfte Commit gleich bleibt. Ein Marketplace-Maintainer hat genau das als Medium-Fund
  gemeldet („mutable-release-binary“: Digest und Binary aus demselben Release, `immutable: false`,
  kein im Quellcode gepinnter Digest). Das Ticket blieb ohne Freigabe offen. Berechtigt, und vorher
  hatte es kein Reviewer im Team gesehen.
- **Reflex für jedes Release mit ausführbarem Artefakt** (Binary, Skript, Container-Image,
  Plugin-Bundle, Installer):
  1. **Digest im Quell-Repo pinnen.** Der Installer prüft gegen den Wert im Commit (z. B. eine
     Lock-Datei `version sha256`), nicht gegen eine `.sha256` aus dem Release. Die darf zusätzlich
     liegen, ist aber kein Identitätsbeweis.
  2. **Provenienz belegen.** CI baut aus dem getaggten Commit und erzeugt eine Attestation
     (GitHub: `actions/attest-build-provenance`, prüfbar mit `gh attestation verify`). Den Build-Lauf
     in die Release-Notes schreiben.
  3. **Releases unveränderlich machen** (GitHub: immutable releases) und Assets nie überschreiben
     (kein `--clobber`). Das allein reicht nicht, gehört aber dazu.
  4. **Reihenfolge:** bauen → Digest committen → genau dieser Commit wird geprüft bzw. eingereicht.
     Der geprüfte Commit muss das ausgeführte Artefakt eindeutig bestimmen.
- **Prüffrage für Gate-Reviews:** „Ändern sich die ausgeführten Bytes, wenn sich nur etwas
  *außerhalb* des geprüften Commits ändert (Release-Asset, `latest`-Tag, CDN, Branch-Head)?" Ja → Fund,
  auch wenn Prüfsummen, TLS und `--fail` sauber aussehen.

## Fremde Validatoren: Grenzen aus deren Code lesen

- **Ein generischer Fehler eines fremden Validators („compatibility validation failed") nennt den
  Grund oft nicht.** Beispiel: ein Plugin-Katalog lehnte ein Update ab, weil die `description` 649
  statt höchstens 500 Zeichen hatte. Die Grenze stand nur im Validator-Code, nicht in der Doku.
- **Reflex:** Vor dem Einreichen bei einem fremden Katalog, Store oder Registry die Feldgrenzen und
  Prüfregeln aus deren Repo lesen (Schema, Validator-Skript) und gegen die eigene Einreichung prüfen.
  Nach einem Fehlschlag zuerst den Fehlercode im Validator-Code suchen, nicht raten.

## Lehren zwischen Bobnets teilen (es fehlt noch ein Weg)

- **Eine Lehre, die nur in einer Instanz landet, hilft genau einer Instanz.** Die beiden Lehren oben
  entstanden im Omarchy-Bob-Bobnet. Einen Weg, sie an andere Bobnets weiterzugeben (Haupt-Bobnet auf der
  VM, Kunden-Bobnets, neue Instanzen), gibt es bisher nicht. Bleibt nur der Umweg über einen PR an die
  Engine. Der braucht Rechte, die eine Instanz oft nicht hat, und Garfield muss ihn bemerken.
- **Reflex:** Eine Lehre, die über das eigene Projekt hinaus gilt, ausdrücklich als „engine-würdig"
  markieren, bereinigt um Projekt- und Kundendaten (keine Namen, Repos, Hosts, Zahlen aus Kundensystemen).
  Dann über den Engine-Maintainer in den Kanon bringen. Ziel für Engine 3.0: ein eigener Kanal, in dem
  Bobnets bereinigte, generische Lehren austauschen. So wie sich Entwickler gegenseitig von ihren
  Stolpersteinen erzählen.
