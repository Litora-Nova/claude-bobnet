# scripts/ — claude-bobnet Toolkit

Universelle Shell-Scripts für das Team-OS. Projekt-spezifische Werte kommen aus
Env-Variablen (siehe `dev-team.env.example`) — die Scripts selbst bleiben generisch.
Pro Projekt: `dev-team.env` aus dem Example ableiten + `source`-en (oder via Onboard).

| Script | Zweck | Wichtigste Env |
|---|---|---|
| `log.sh <Agent> <status> <msg>` | Heartbeat in `<STANDUP_DIR>/<Agent>.log` | `STANDUP_DIR`, `DEV_TEAM_TZ` |
| `scut.sh "<msg>" [info\|mid\|urgent]` | Lead → Mensch (Telegram-Ping) | `SCUT_SECRETS_DIR` |
| `scut-poll.sh` | Mensch → `_inbox.md` (+ optionale Live-Injection via `lib/mux.sh`), Long-Poll-Daemon | `SCUT_*`, `STANDUP_DIR`, `TEAM_LEAD` |
| `lib/mux.sh` | Multiplexer-Adapter (tmux\|zellij): `mux_spawn/has/list/send/capture/kill` — Daemons & Dashboard rufen nie direkt tmux/zellij | `BOBNET_MUX` |
| `qa-add.sh "<frage>" "<antwort>"` | Q&A-Eintrag in `<STANDUP_DIR>/qa/` | `STANDUP_DIR`, `QA_ASKED_BY`, `QA_ANSWERED_BY` |
| `cron/*` | Geplante Jobs (standup/recap/health/bugcheck) | ⚠️ **noch hart-codiert** |

**Secrets** (`telegram_token`, `telegram_chat_id`, `telegram_offset`) liegen in
`$SCUT_SECRETS_DIR` (gitignored, out-of-band via scp/Syncthing) — NIE committen.

> **cron/ — Phase 4:** Die Cron-Scripts sind 1:1 aus der Acme-Instanz übernommen und
> enthalten noch hart-codierte Werte (Staging-Host, Repo-Liste, BobNet-Port, LXC-Pfade).
> Parametrierung + Umstellung auf **GUPPI** (Routine-Executor) erfolgt in Phase 4.
