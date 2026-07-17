# Bobiverse — Knowledge Base (Einstieg & Landkarte)

> „Wie funktioniert das hier eigentlich?" — dieser Einstieg beantwortet die großen Linien und
> zeigt für jedes Thema die **kanonische Quelle**. Er dupliziert bewusst nichts (Doc-Drift),
> er verweist. Für den Aufbau eines neuen Teams: Skill `init-bobs`. Zum Aktuell-Halten:
> Skill `update-bobs`.

## Das große Bild (3 Ebenen)

```
Bobiverse        die ganze Installation (Root-Konfig: ~/.claude/bobiverse.json)
├─ BobNet        Singleton · OPTIONAL · Render-Hub/Dashboard für ALLE Teams (:3030)
├─ Colonel       Singleton · Disziplin-Wächter (Prozesse / Sync / Lead-orchestriert?)
└─ Projekt-Bobiverse (pro Ordner) → Bob#1 (Team-Lead) + SCUT + GUPPI + Team-Bobs + Helfer
```

Die **Engine** (dieses Repo) liefert die Mechanik; jedes Projekt **referenziert** sie nur
(Symlinks: `skills`/`team-rules`/`memory` + generierte Hook-Wrapper + kleine Instanz-Config
`_dev_team/dev-team.env`). Engine-Update = `update-bobs` → erreicht jedes Projekt; Instanz-State
(Standup, env, agents, memories) bleibt dabei garantiert unangetastet (`bin/upgrade`).

## Wie ein Team funktioniert

- **Archetypen-Katalog statt fester Belegschaft** — Rollen (backend, review, design, advisor, …)
  sind getypte Definitionen in [`archetypes/`](../archetypes/README.md); der Lead spawnt sie
  bei Bedarf. Jede Rolle bringt Model+Effort-Default mit (`scripts/lib/model.sh`); der
  `advisor` (stärkstes Modell, on-demand) ist die Zweitmeinung für die großen Brocken.
- **Circle-of-Trust + Tiers (T1–T4)** — was ein Agent autonom darf und wo der Mensch gated:
  [`team-rules/tiers.md`](../team-rules/tiers.md) + `circle-of-trust.md`. Harte Grenze T4:
  Production / Secrets / DNS / History-Rewrite.
- **Gates** — Builder ≠ Reviewer; Review/Compliance/Tests sind eigene Bobs mit Audit-File;
  genau EIN Merge-Owner integriert. Welcher Gate für welchen Diff: `bin/tier` (gate-tiering).
- **Rollen-Trigger** — on-demand-Rollen laufen verpflichtend bei Trigger-Events (z. B. `docs`
  bei `feierabend`): `archetypes/*.json` → `triggers`.
- **Routinen** — Boot → Stand-up → Feierabend, inkl. Sync- und Commit-Pflichten:
  [`team-rules/routines.md`](../team-rules/routines.md) + `sync.md`.

## BobNet-Dashboard (:3030)

Das Live-Fenster in alle Teams (`dashboard/`, Nuxt). Es zeigt pro Tenant (`?project=<uid>`):

- **Roster** — Team-Karten mit Persona, Avatar, Rolle (Log-Key `uid` → Persona via Theme +
  `team.config.json`-Overrides)
- **Heartbeats/Activity** — der Live-Puls aus `<standup>/*.log` (busy/idle/blocked/done)
- **Inbox** — die letzten Agent-zu-Agent-Nachrichten des Teams
- **Plan/Goal** — Roadmap-/Zielartefakte des Projekts (`plan/`, GOAL)
- **Multi-Tenant** über die Projekt-Registry (`projects.registry.json`): jedes registrierte
  Projekt ist ein Tenant mit eigenem `standupDir`
- **`/api/health`** — tenant-neutrale Liveness-Probe (Basis für Supervisor/Watchdog der Instanz)

Betrieb: Start über den Launcher (`bin/start` bzw. Dashboard-Launcher der Installation);
Dauerbetrieb/Selbstheilung ist Instanz-Sache (z. B. systemd-User-Units — Runbook der Installation).

## Kommunikation

| Kanal | Wofür | Kanon |
|---|---|---|
| **Heartbeat** (`scripts/log.sh <uid> <status> "<satz>"`) | Sichtbarkeit: wer macht was | `team-rules/heartbeat.md` |
| **Projekt-Inbox** (`<standup>/_inbox.md`) | Agent-zu-Agent IM Team, @-adressiert, append-only | `team-rules/comms.md` |
| **News-Box** (`scripts/news.sh`) | Broadcast an ALLE Teams der Installation (Releases, neue shared Tools/MCPs + How-to-Pfad) | `team-rules/news.md` |
| **SCUT / Telegram** | Mensch ↔ Team von unterwegs: `scut-poll.sh` (inbound → Inbox, Media-Download), `scut.sh "<text>" [info\|mid\|urgent]` (Antwort). EIN Poller pro Bot-Token! | `scripts/scut-poll.sh` Header |
| **Multiplexer** (`scripts/lib/mux.sh`) | tmux/zellij-Adapter für Session-Checks + best-effort Live-Inject (Inbox-first bleibt Default). Kanon seit #64: **tmux = Fleet-Default für headless Betrieb**, zellij nur noch für interaktive Sessions (deprecatet für headless, s. `mux.sh`-Kopf) | `team-rules/comms.md` + `scripts/lib/mux.sh`-Kopf |
| **Bobiverse-Sync** (`bin/sync-share`) | Lese-/Edit-Fenster für Mensch + externe Coworker (Inbox/Plan/share) — kein State-Sync | `team-rules/comms.md` §6 |

## Geteilte Tools (`bin/` + `scripts/`)

- `bin/install` / `bin/onboard` — Bobiverse installieren / Projekt anschließen (Skill `init-bobs`)
- `bin/upgrade` + `bin/check-compat` — Engine-Update mit Schema-Anker (Skill `update-bobs`)
- `bin/sync` — fetch/pull/push-Routine je Projekt · `bin/who-owns` — wem gehört Pfad/Thema?
- `bin/tier` — Gate-Klassifizierung für einen Diff · `bin/start` — Dashboard-Launcher
- `scripts/image-gen.sh` — geteilte Bild-Generierung (zentraler Secrets-Store)
- `scripts/colonel.sh` + `scripts/cron/` — Disziplin-Audit + Cron-/Timer-Jobs

## Wo finde ich was?

| Frage | Quelle |
|---|---|
| Welche Rollen gibt es, wer kriegt welches Modell? | `archetypes/README.md` |
| Was darf ein Agent autonom? | `team-rules/tiers.md` + `autonomy.md` |
| Wie läuft ein Tag (Boot/Stand-up/Feierabend)? | `team-rules/routines.md` |
| Wie reden Agenten/Teams/Menschen miteinander? | `team-rules/comms.md` + `news.md` |
| Wie committe ich richtig (Identität, Trailer)? | `team-rules/commits.md` |
| Wie funktioniert das Dashboard technisch? | `dashboard/CLAUDE.md` + `dashboard/README*` |
| Wie kommt ein neues Projekt dazu? | Skill `init-bobs` |
| Wie bleibt ein Projekt aktuell? | Skill `update-bobs` |
