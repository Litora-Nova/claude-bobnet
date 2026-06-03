# claude-dev-team

Engine + Library für Tech-Lead-orchestrierte KI-Dev-Teams: BobNet-Dashboard, Rollen-Archetypen,
Themes, Heartbeat/Inbox/Gate-Prozesse, Sprint-Lifecycle. **Universell, versioniert** — alle
Projekte (und später Community) profitieren von Updates.

## Struktur
| Verzeichnis | Inhalt | Kommt in |
|---|---|---|
| `dashboard/` | Nuxt-Dashboard-Engine „BobNet" (config-driven; ex-`acme-bobiverse`) | Phase 1 |
| `archetypes/` | Rollen-Definitionen (Schicht ① Struktur) | Phase 2 |
| `themes/` | `bobiverse/` `formal/` `minimal/` (Schicht ② Flavor) | Phase 2 |
| `scripts/` | `log.sh` `scut.sh` `cron/*` (parametriert) | Phase 1 |
| `hooks/` | SessionStart-Heartbeat, deploy-guard (parametriert) | Phase 4 |
| `schemas/` | `team.config`-Schema, sprint-lifecycle, frontmatter-specs | Phase 2/4 |
| `bin/` | `onboard` — idempotente Setup-Prozedur (Symlinks pro Maschine) | Phase 3 (geplant — bin/ ist noch nur .gitkeep) |
| `docs/` | Schnittstellen, Features, Configs (BobNet-Doku) | laufend |

## Die 3 Schichten
**① Archetyp** (Struktur, universal) · **② Theme** (Flavor — Bobiverse = eines) · **③ Instanz** (`<projekt>/_dev_team/`, committed).

**Default-Theme:** `minimal` (Release) · `bobiverse` = die hauseigene Flavor (Dennis-E.-Taylor-Homage).
**Harte Regeln:** [`CONVENTIONS.md`](./CONVENTIONS.md) — beschreibende Namen/IDs (nie `agent1`/`p0`),
Bild-statt-Emoji, Sync=Git, Style-Abstimmung.

> **Status:** Phase 2 ✓ (Archetypen + Theme-System + Engine theme-driven). Phase 3 = **offen** (lokal konsolidieren / `_dev_team/`; `bin/onboard` noch nicht vorhanden — `bin/` ist nur `.gitkeep`).
