# Cron-Jobs — 24/7-Habitat (LXC `claude`)

> Laufen auf der LXC (Host/User aus `dev-team.env`), Zeit = **Europe/Berlin** (`CRON_TZ`).
> Skripte: `standup/cron/`. Sammel-Log: `~/cron.log`. Verwaltung: `crontab -l` / `crontab -e`.
> **Report-only / Staging — KEINE Prod-/Deploy-Aktion** (Tier-4 = Mensch, siehe `TEAM.md` / Memory `circle-of-trust-tiers`).

## Übersicht
| Zeit (Berlin) | Job | Typ | Output | SCUT |
|---|---|---|---|---|
| **06:30** | Morgen-Standup | `claude -p` (Bob) | `standup/report-standup-DATE.md` | 🟢 immer, kurz |
| **00:00** | Recap & Report & Feedback | `claude -p` (Bob) | `standup/report-DATE.md` | 🟢 „gute Nacht" |
| **04:00** | Bug- & Update-Check | bash | append `standup/_bugs.md` | 🔴 nur bei High/Crit |
| **alle 2 h** | Health-Watch | bash | (cron.log) | 🔴 nur bei Ausfall |

## Was jeder Job tut
- **cron-standup.sh** — git-log 24 h + letzte Heartbeats + offene Tasks (`_sprint.md`) + letzter Bug-Check → Bob (`claude -p`) textet kurzen Standup → Report + 🟢 SCUT. Fallback: Rohdaten, falls `claude -p` leer.
- **cron-recap.sh** — Commits des Tages + Sprint-Stand → Bob schreibt Tagesabschluss (`report-DATE.md`) + 🟢 SCUT.
- **cron-bugcheck.sh** — pro Repo `npm audit` (wenn `node_modules` da), sonst „Deps fehlen → skip"; append `_bugs.md`; 🔴 SCUT nur bei High/Crit.
  - **⚠️ Voll-Coverage** (Test-Suiten + Brakeman + bundle-audit) braucht erst Repo-Deps auf der LXC: `bundle install` BE (**ruby 3.3.5 vs 3.4.2 klären**) + `npm install` FE/Web. Bis dahin nur npm-audit der installierten Repos.
- **cron-health.sh** — Staging-URL (200?) + BobNet `:3030` (200?) + SSL-Restlaufzeit (< 14 d?). 🔴 SCUT nur bei Problem, sonst still.

## Verwaltung
```bash
ssh <user>@<lxc-host>
crontab -l                 # Jobs anzeigen
crontab -e                 # Jobs bearbeiten
tail -f ~/cron.log         # Live-Log
bash ~/Sites/<project>/standup/cron/cron-health.sh   # manueller Test (jeder Job einzeln startbar)
```
- Skripte liegen auf Mac **und** LXC unter `standup/cron/` — nach Änderung syncen (`scp`).

## Verwandte Daemons (kein cron, laufen im Multiplexer: tmux|zellij, s. `lib/mux.sh`)
- **`scut`:** `scut-poll.sh` = SCUT-Inbound (Telegram → `_inbox.md` + optionale Live-Injection an `acme_bob`).
- **`bobnet`:** BobNet-Dashboard `:3030`.
- **Outbound-Helfer:** `standup/scut.sh "<kurz>" [info|mid|urgent]` (Bob → Mensch).

## Mechanik-Notizen
- `claude -p` **braucht `</dev/null`** in Skripten (liest sonst stdin und frisst Folge-Zeilen). Lädt Bobs Persona + Memories.
- Narrativ = LLM (`claude -p`), mechanisch = bash. ~2–4 LLM-Läufe/Tag.

## inbox-watch (Issue #44)

`scripts/inbox-watch.sh` = EIN Durchlauf pro Aufruf; Kadenz macht der Host-Timer (Empfehlung
2–5 min, analog health). Das Script serialisiert sich seit #48/0.14.0 selbst per `flock`
(`<STATE_DIR>/.lock`) — ein überlappender Zweitlauf (z. B. wenn ein Durchlauf mal länger
braucht als das Timer-Intervall) wird sauber übersprungen statt parallel zu laufen; kein
externes `flock`-Wrapping im Timer/Cron nötig. Beispiel systemd-Timer (Instanz-Seite; Enable =
`{HUMAN}`, T4):

```ini
# ~/.config/systemd/user/inbox-watch.service
[Service]
Type=oneshot
ExecStart=%h/path/to/engine/scripts/inbox-watch.sh

# ~/.config/systemd/user/inbox-watch.timer
[Timer]
OnCalendar=*:0/3
Persistent=true
```

Cron-Äquivalent: `*/3 * * * * <engine>/scripts/inbox-watch.sh >> <standup>/inbox-watch.log 2>&1`.
Instanz-Kontrakt (`dev-team.env`: `TEAM_LEAD`/`MUX_SESSION`/`BOOT_CMD`/`INBOX_WATCH_ALERT_CMD`)
im Script-Header. Seit #48 ist Zustellung heartbeat-verifiziert (Re-Nudge + optionaler
Eskalations-Hook statt sofortigem Finalisieren) — Details ebenfalls im Script-Header.
