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
| `telegram.sh` | **funktional** (long-poll getUpdates → Events; baut auf `../scut.sh`/`../scut-poll.sh`-Secrets). `SCUT_TG_ONESHOT=1` für einmaliges Pollen, `SCUT_TG_FAKE_RESPONSE_FILE` = Testmodus ohne Bot-Token/Netzzugriff (analog `SCUT_MAIL_EML_DIR`). |
| `email.sh` | **funktional** (IMAP readonly-Poll → Events; Secrets env-var ODER `SCUT_SECRETS_DIR/email_*`; UID+UIDVALIDITY-Offset; Subject-Tag/Plus-Adresse-Triage; `SCUT_MAIL_ONESHOT=1` für einmaliges Pollen, `SCUT_MAIL_EML_DIR` = Testmodus ohne Server). **Attachments (#46):** mit `SCUT_MAIL_ATTACH_DIR` persistiert der Adapter Volltext + Anhänge als `<prefix>-*`-Dateien (ASCII-sanitiert, Size-Cap `SCUT_MAIL_ATTACH_MAX`); unset = nur zählen. **Persistenz-Fehler (#50):** Default = best-effort (zustellen + Offset vor + Vermerk, Recovery via Anker-Rewind); `SCUT_MAIL_ATTACH_STRICT=1` = Offset nicht vorrücken, UID kommt erneut (kein Anhang-Verlust, kann bei Dauerfehler stallen). **Known-Sender-Mapping (#53):** dritter, niedrigster Fallback (nach Subject-Tag/Plus-Adresse) — bekannte `From:`-Adresse aus `SCUT_MAIL_SENDERS_FILE` (Default `$PROJECT_ROOT/_dev_team/team-rules/scut-mail.senders`, Instanz-Daten) → gerichtet an `@<Agent>` (Default `TEAM_LEAD`) statt ungerichtet in die Review-Queue. |
| `github.sh` | Stub (`--demo`) — TODO `gh api notifications` + Repo→uid. |
| `teams.sh` | Stub (`--demo`) — TODO Graph-API/Webhook. |

## Verwandt, aber KEIN Router-Channel

Die **Cross-Installation-Bridge** (Issue #45) läuft bewusst NICHT über den Router:
`../bridge-receive.sh` (forced-command-Ziel, Pflicht-Adressierung `[uid]`, stempelt
serverseitig, flock-Append + Audit) + `../bobnet-send.sh` (peers.json). Eigener
Trust-Pfad — Schlüssel/`authorized_keys` = Instanz + `{HUMAN}` (T4).
Der Sender schickt die Nachricht **immer auf stdin, nie als SSH-Kommando** (#49); der Peer
muss in `peers.json` als `"forced": true` (forced-command-Empfänger liest stdin) oder mit
`"recv": "<remote-cmd>"` deklariert sein, sonst verweigert der Sender (fail hard).

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
