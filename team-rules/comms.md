# team-rules/comms.md — Agent-zu-Agent-Kommunikation: Inbox-first (Engine-Canon)

> Wie Agenten über Bobiverse-Grenzen hinweg miteinander sprechen. **Default = asynchron über die
> Inbox des Ziel-Bobiverse**; Prompt-Injection ist die Notfall-Ausnahme, nie der Normalweg.
> Tokens: `{TEAM_LEAD}` = Projekt-Lead, `{HUMAN}` = Product Owner.
> Projekt-Override: gleichnamiges File unter `_dev_team/team-rules/comms.md` (Engine = Fallback).

## Warum (PO-bestätigt 2026-06-10)

Direkte Prompt-Injection (`tmux send-keys` in die Eingabezeile einer fremden Session) hat drei
empirisch teure Probleme:

- **Unterbricht aktive Tasks** — die Ziel-Session verliert ihren Faden mitten in der Arbeit.
- **Kollidiert mit ungesendeten Eingaben des `{HUMAN}`** — real passiert: hängende GOs,
  vermischte Nachrichten im Eingabe-Buffer.
- **Nicht auditierbar** — was injiziert wurde, steht in keinem Log; niemand kann nachvollziehen,
  wer wann was gesagt hat.

Die Inbox hat keines dieser Probleme: asynchron, auditierbar, kollisionsfrei.

## Kanon

1. **DEFAULT Agent-zu-Agent = Inbox des ZIEL-Bobiverse** (`<standup>/_inbox.md`): append-only,
   adressiert per `@<Name|UID>`, signiert, mit Datum. Format:
   ```
   YYYY-MM-DD HH:MM | @Empfänger | Text — (Absender)
   2026-06-10 14:30 | @acme-backend-dev | Schema-Frage zu X, Details in Y — (acme-review)
   ```
   Zustellung ist **garantiert**, weil jede Heartbeat-/Standup-Routine die Inbox liest
   (siehe `routines.md` / `heartbeat.md`) — der Empfänger holt die Nachricht ab, wenn er
   ohnehin den Kopf hebt.
2. **Inbox ist append-only.** Fremde Zeilen nie umschreiben oder löschen — deckt sich mit der
   bestehenden Regel zu geteilten `_*.md`-Dateien.
3. **Antworten ebenfalls via Inbox** — in die Inbox des *fragenden* Bobiverse. Niemand wartet
   synchron auf den anderen; wer eine Antwort braucht, schreibt sie sich auf die offene Liste
   und arbeitet weiter.
4. **Prompt-Injection NUR für echte Notfälle** — T4-Blocker oder der `{HUMAN}` wartet live.
   Und dann mit voller Sorgfalts-Routine (siehe auch `lessons.md`, Multiplexer-Abschnitt). Das
   Prinzip ist **multiplexer-neutral** (tmux ODER zellij — Default `auto`, tmux-bevorzugt):
   - **erst capturen**: Zustand + ungesendete Eingaben des Ziels prüfen;
   - **capture und send NIE im selben Befehl**;
   - **Text und Enter SEPARAT** senden (nie Text+Newline in einem Rutsch).

   **Bevorzugter Weg = die `mux_*`-Verben aus `scripts/lib/mux.sh`** — die einzige Stelle, die
   weiß, welches Backend aktiv ist (`BOBNET_MUX=tmux|zellij|auto`). Nie direkt `tmux`/`zellij`
   aufrufen:
   - `mux_capture <NAME>` → sichtbarer Pane-Inhalt nach STDOUT (Zustand prüfen);
   - dann, in **getrenntem** Aufruf, `mux_send <NAME> "<text>"` (sendet Text + Enter).

   Wer das Backend doch von Hand fährt (Debug), das verifizierte Befehls-Mapping:

   | Schritt | tmux | zellij |
   |---|---|---|
   | Zustand capturen | `tmux capture-pane -p` | `zellij --session NAME action dump-screen` (→ STDOUT, **kein File-Arg** in 0.44) |
   | Text senden | `tmux send-keys -l "<text>"` | `zellij --session NAME action write-chars -- "<text>"` |
   | Enter (separat!) | `tmux send-keys Enter` | `zellij --session NAME action write 13` |
   | Sessions listen | `tmux ls` | `zellij list-sessions --no-formatting --short` |

   **zellij-Grenze (verifiziert):** `write-chars`/`dump-screen` wirken NUR zuverlässig auf
   Sessions mit angebundenem **Client**; gegen rein detached Sessions sind send/capture
   best-effort. Umso mehr gilt: der Injection-Pfad ist Notfall, nicht Normalweg.

   Alles andere: Inbox. **Inbox-first bleibt der Default — über beide Multiplexer.**
5. **Eskalation, wenn Inbox zu langsam wäre:** den eigenen Heartbeat-Status auf **`blocked`**
   setzen — das Dashboard zeigt blocked prominent/urgent, der Hilferuf ist sichtbar, ohne
   fremde Prompts zu kapern. Perspektivisch übernimmt ein Comms-Router-/Concierge-Dienst die
   Weck-Funktion sauber; bis dahin gilt: blocked + Inbox, nicht Injection.

## §6 Bobiverse-Sync — Transport zum `{HUMAN}`-Gerät & für externe Coworker (PO-Design 2026-06-10)

Damit der `{HUMAN}` (und externe Coworker-Agenten auf seinen Geräten) Inbox + Plan-Artefakte
**ohne Formulare und ohne Shell** lesen und editieren können, wird pro Projekt ein
Datei-Sync eingerichtet (Werkzeug: ein Continuous-Sync-Dienst à la Syncthing). Kanon:

1. **Die Projekt-Wurzel ist die Share-Wurzel — aber Whitelist-only.** Eine generierte
   `.stignore`-Whitelist (via `bin/sync-share`, Items aus `team-rules/sync-share.items`)
   lässt NUR die Mensch-Artefakte durch — Default: `_inbox.md` (Nachrichten-Inbox) ·
   `_inbox/` (Datei-Drops) · `plan/` (GOAL.md, ROADMAP.md, PLAN_*) · `share/` (Freifläche
   für externe Coworker/Services). **Alles andere (Repo, `.git`, Secrets, Code) bleibt
   lokal.** Keine Symlinke, kein Extra-Ordner: alles bleibt git-versioniert an Ort und Stelle.
2. **Geräte-Seite einmalig:** Auto-Accept für das Server-Gerät + Default-Ordnerpfad
   (z. B. `~/Bobiverse-sync/`) setzen → jeder neue Projekt-Share erscheint dort von selbst,
   ohne weitere Bestätigungen. **Benennung (PO-Kanon 2026-06-11):** Share-**ID** = immutable
   `PROJECT_UID` (`--uid`), Share-**LABEL** = menschlicher **Projektname** (`--name`, z. B.
   „Acme Inc") — Auto-Accept benennt den Geräte-Ordner nach dem LABEL, der Mensch sieht also
   Projektnamen, die Maschine routet auf UIDs. Daneben kann ein genereller `exchange`-Share
   für Projekt-Übergreifendes bestehen.
3. **Die `.stignore` ist heilig.** Sie ist die einzige Bremse — fehlt sie, ginge das ganze
   Projekt (inkl. `.git`/Secrets) auf Reisen. Nie löschen/editieren außer über
   `bin/sync-share` (das Tool generiert sie bei jedem Lauf deterministisch neu —
   Hand-Edits werden bewusst überschrieben); eine Wach-Routine (Colonel/Routinen-Kanon)
   prüft ihre Existenz. **Secrets gehören NIE in die Whitelist** — das Tool verweigert
   Secret-artige Items (`.env*`, credentials, Keys/PEM, database/configuration.yml, …)
   sowie Glob-/Traversal-Items.
4. **Externe Coworker sind Flotten-Teilnehmer zweiter Ringe:** sie schreiben in die
   gesyncte `_inbox.md` nach §-Kanon oben (adressiert, signiert, datiert, append-only)
   und nutzen `share/` für Dateiübergaben. Sync-Konflikt-Dateien (`*.sync-conflict-*`)
   werden nicht ignoriert, sondern von der Standup-Routine gemerged/gemeldet.
   **Onboarding-Vorlage:** `skills/init-bobs/templates/SYNCTHING_COWORKER.template.md`
   — Platzhalter ersetzen, in den projekteigenen `share/` legen (synct selbst zum Coworker).
   **Der projektübergreifende `exchange`-Share ist KEIN Projekt-Zuhause** — niemals
   Projekt-Ordner dort ablegen, um sich eine eigene Share-Registrierung zu „sparen";
   jedes Projekt bekommt seinen EIGENEN Share auf der Projekt-Wurzel.
   **Share-Registrierung ist Server-/Infra-Ebene:** scheitert `--register` am Harness
   eines Projekt-Agenten (Sync-Dienst-Config = systemweite Änderung), legt er die
   lokalen Artefakte mit `--no-register` an und fordert die Registrierung per Inbox
   beim Hub-Lead/Serverwächter an — NICHT improvisieren.
   **Erlaubte Rollen-Variante (PO-Entscheid pro Projekt):** eine in-house Rolle (z. B.
   `design`) ist Owner + **einzige Liefer-Instanz** ihrer Domäne; ein externer Coworker
   derselben Domäne darf ZUSÄTZLICH als optionaler Ideengeber/Reviewer angebunden bleiben —
   nie als Liefer-Quelle, nie als Abhängigkeit (das Team liefert auch ohne ihn). Default
   bleibt: die in-house Rolle löst den externen Coworker ab.
5. **Plan-Artefakte:** kanonischer Ort ist `<projekt>/plan/` — `{HUMAN}`/Lead editieren,
   Agenten lesen und schlagen Änderungen per Inbox vor (minimiert Schreibkonflikte).
6. **Abgrenzung zu `sync.md`:** Der Datei-Sync ist ein **Lese-/Edit-Fenster für Menschen
   und externe Coworker**, KEIN State-Sync — der State-Sync der Maschinen bleibt Git über
   `origin` (`sync.md`). Gesyncte, git-versionierte Artefakte (z. B. `plan/`) committet
   die normale Standup-/Feierabend-Routine als Human-Edits.
