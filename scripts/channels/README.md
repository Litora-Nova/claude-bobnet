# scripts/channels/ — SCUT-Channel-Adapter

Jeder Adapter wandelt einen **eingehenden Kommunikations-Kanal** (Telegram, Email, GitHub, Teams …)
in ein **normalisiertes Event** um und gibt es auf stdout aus. Der Core-Router
[`../scut-router.sh`](../scut-router.sh) konsumiert diesen Strom und triagiert/routet ihn
datengetrieben (aus `projects.registry.json` [+ optional `team.config`]).

```
┌─────────────┐   normalisierte Events (TSV)   ┌──────────────┐   gerichtet → _inbox.md des Ziel-Bobiverse
│ channels/   │ ─────────────────────────────► │ scut-router  │ ─►
│ <kanal>.sh  │                                │   .sh        │   ungerichtet → _review-queue.md (Kontext-Bobiverse)
└─────────────┘                                └──────────────┘
```

## Normalisiertes Event-Format (TSV, 6 Felder)

```
channel   external_id   ts_epoch   sender   target   text
```

| Feld | Bedeutung |
|---|---|
| `channel` | Herkunft: `telegram` \| `email` \| `github` \| `teams` |
| `external_id` | channel-eigene ID (Dedup/Offset) — vom Adapter verwaltet |
| `ts_epoch` | Unix-Timestamp des Events |
| `sender` | Absender-Identität des Channels |
| `target` | `@<Agent>` · `[<uid>]` · `[<uid>]@<Agent>` · **leer** (= ungerichtet) |
| `text` | Nachrichtentext (Tabs/Newlines zu Spaces normalisiert) |

## Triage (im Router)

- **gerichtet** (`@X` / `[uid]`) → in die `_inbox.md` des Ziel-Bobiverse. `[uid]` ohne Agent → an den
  `TEAM_LEAD` dieses Projekts. `@Agent` ohne `[uid]` → an diesen Agenten im **Kontext-Bobiverse**
  (`CONTEXT_UID` = das Bobiverse, dessen Channel die Nachricht empfing).
- **ungerichtet** → `_review-queue.md` des Kontext-Bobiverse = die „muss jemand prüfen"-Queue.

## Status

| Adapter | Stand |
|---|---|
| `telegram.sh` | **funktional** (long-poll getUpdates → Events; baut auf `../scut.sh`/`../scut-poll.sh`-Secrets). `SCUT_TG_ONESHOT=1` für einmaliges Pollen. |
| `email.sh` | Stub (`--demo` zeigt das Format) — TODO IMAP/maildir. |
| `github.sh` | Stub (`--demo`) — TODO `gh api notifications` + Repo→uid. |
| `teams.sh` | Stub (`--demo`) — TODO Graph-API/Webhook. |

## Verifikation

```bash
# Router-Triage ohne echte Channels (Demo-Registry, prüft alle 4 Routing-Pfade):
scripts/scut-router.sh --self-test

# Stub-Adapter → Router (Dry-Run, schreibt nichts, berichtet die Entscheidungen):
SCUT_ROUTER_DRYRUN=1 scripts/channels/email.sh --demo | scripts/scut-router.sh

# Telegram einmal pollen → Router (echte Secrets nötig):
SCUT_TG_ONESHOT=1 scripts/channels/telegram.sh | scripts/scut-router.sh
```

## Was NICHT hierher gehört

Interne Same-Project-Comms (Agent↔Agent im selben Bobiverse via `standup/_inbox.md`) laufen weiter
**direkt** — der Router ist nur für **externe** Channel-Eingänge (Mensch/Service → Bobiverse).
