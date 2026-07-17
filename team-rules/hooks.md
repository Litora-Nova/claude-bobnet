# team-rules/hooks.md — Hook-Registry (DIE Quelle der Wahrheit)

> 📐 **Struktur-Prinzip:** Diese Tabelle deklariert, **welche Hooks es gibt**. Die Scripts unter
> `hooks/` implementieren nur, was hier steht, und lesen ihre Regeln aus der **beschreibenden
> Schicht** (`team-rules/*` + `dev-team.env`). **Neuer Hook / neue Regel = Daten editieren
> (diese Tabelle + ggf. ein `team-rules/*`-File), NICHT Code in den Scripts vergraben.**
>
> `team-rules/*` = beschreibende, themable/projekt-überschreibbare **Daten**.
> `hooks/*` = generische **Mechanik**.

## Registry

| Hook | Trigger | Zweck | Regel-Quelle (Daten/Env) | aktiv? |
|---|---|---|---|---|
| `deploy-guard.sh` | PreToolUse — Edit\|Write\|MultiEdit (Pfad) · Bash (Befehl) | Dreistufig: **blockt** Edits an Production-/Secret-Pfaden (Exit 2, Tier-4 human-only) · **erzwingt Bestätigung** (`permissionDecision:"ask"`) für Deploy-Config-Edits · **erzwingt Bestätigung + exakten Ablauf** für Deploy-*Befehle* (Bash, opt-in) — `{HUMAN}` bestätigt jeden Edit/Deploy einzeln, nie auto-accept (PO-Doktrin 2026-06-10 + §17 2026-06-13, `tiers.md`). | `deploy-guard.paths` (Block) + `deploy-guard.ask.paths` (Ask) + `deploy-guard.commands` (Befehl-Globs, opt-in, KEIN Floor) + `deploy-guard.procedure` (Ablauf-Text); Fallback: eingebaute Defaults/Floors | ⊘ gebaut, NICHT verdrahtet (Stufe C) |
| `session-sync-reminder.sh` | SessionStart | Rendert den State-Sync-Reminder (Branch-Check + fetch/pull/push über die Repos). | `team-rules/sync.md` (`REMINDER:`-Block) + Env `PROJECT_NAME`, `CANONICAL_BRANCH`, `DEV_TEAM_REPOS` | ⊘ gebaut, NICHT verdrahtet (Stufe C) |
| `session-heartbeat.sh` | SessionStart | Schreibt einen Heartbeat des arbeitenden Agents (`log.sh $AGENT busy session-start`) ins BobNet der Kollab-Instanz. Default-Agent = Lead; shared Services setzen `HEARTBEAT_AGENT`. Fail-safe, blockt nie. | Env `HEARTBEAT_AGENT` (Default `TEAM_LEAD`) + `STANDUP_DIR` aus `dev-team.env` + `team-rules/heartbeat.md` → `scripts/log.sh` | ⊘ gebaut, NICHT verdrahtet (Stufe C) |
| `context-trim.sh` (→ `context-trim.py`) | PostToolUse (Bash\|Read\|MCP) | Token-Win (Headroom-Konzept nativ): kürzt das **größte Text-Feld** übergroßer Tool-Outputs (Kopf+Schwanz+Pointer) via `updatedToolOutput`, **stasht den Volltext** (Bob holt Details on-demand via Read/grep). Struktur-erhaltend (spiegelt `tool_response`) → immun gegen die Schema-Unsicherheit. **FAIL-SAFE:** jede Unsicherheit/kein python3/unter Schwelle → pass-through (Original bleibt). | `team-rules/context-trim.conf` (`CT_THRESHOLD_BYTES`/`CT_HEAD_LINES`/`CT_TAIL_LINES`/`CT_STASH_DIR`; Projekt-Override > Engine > Default) | ⊘ gebaut, NICHT verdrahtet (Stufe C — erst gegen Live-Payload verifizieren, Schema noch nicht stabilisiert) |
| `pre-push-identity-floor.sh` | **git `pre-push`** (KEIN Claude-Code-Hook, s. Konventionen unten) | Client-seitiger Floor vor jedem `git push` (Issue #59): blockt, wenn Autor/Committer eines neu gepushten Commits nicht dem Kanon-Format aus `commits.md` entspricht ODER (falls `DEV_TEAM_EMAIL` auflösbar) eine fremde Mail-Domain trägt — als Metadaten ODER im committeten Inhalt (Feld-Fund: eine private Mail-Adresse landete als Commit-Autor in einem öffentlichen Repo). Zusätzlich ein kurzes, bekanntes Secret/Token-Muster-Set (AWS-Key, PEM-Private-Key-Header, GitHub/GitLab/Slack-Token-Präfixe). **Ist ein Floor, kein Ersatz** für die Compliance-Gate-Beurteilung — dokumentierter Bypass `BOBNET_PUSH_FLOOR_SKIP=1 git push`, loggt den Skip trotzdem laut. | `DEV_TEAM_EMAIL` (dev-team.env, optional — ohne sie prüft der Floor nur die FORM, keine Domain) | ✓ aktiv, sobald `bin/onboard` gelaufen ist — **kein** zusätzlicher settings.json-Schritt nötig (git ruft `.git/hooks/pre-push` direkt auf, sobald die Datei dort ausführbar liegt) |

**Status-Legende:** ✓ aktiv (in `.claude/settings.json` verdrahtet, oder bei Git-Hooks: Wrapper liegt ausführbar in `.git/hooks/`) · ⊘ gebaut, nicht verdrahtet · ✗ deaktiviert.

> Alle drei Hooks sind in W3 **gebaut + `bash -n`-sauber**, aber bewusst NICHT in die
> `.claude/settings.json` des Live-Projekts verdrahtet — das ist **Stufe C** (Scharfschalten,
> braucht human-OK). `bin/onboard` (Baustein 4 „Hook-Install") übernimmt die Verdrahtung beim
> Onboard eines Projekts.

## Konventionen (für jeden Hook)

- **Env zuerst:** `source` das nächstgelegene `dev-team.env` (Projekt > Engine-Default), dann die `team-rules/`-Daten.
- **Fail-safe:** SessionStart-Hooks dürfen die Session NIE blocken — bei Fehlern still `exit 0`.
  Nur `deploy-guard` darf bewusst blocken (`exit 2`), und nur bei echtem Pfad-Treffer.
- **stdin-Vertrag (PreToolUse):** Hook bekommt das Tool-JSON auf stdin. `deploy-guard` zieht
  `file_path` UND `command` jq-frei heraus (Regex), damit kein jq-Dependency nötig ist. Die
  Command-Stufe (Bash) ist opt-in und greift nur ohne `file_path` (echtes Bash-Tool).
- **Pfad-Auflösung:** Hooks leiten ihr Engine-ROOT relativ zu `${BASH_SOURCE[0]}` ab — kein hartkodierter Pfad.
- **Daten vor Code:** Globs/Texte/Repos kommen aus `team-rules/*` bzw. Env, nie aus dem Script-Body.
- **Ausnahme Git-Hooks** (`pre-push-identity-floor.sh`, #59): kein Claude-Code-Trigger, sondern
  git's eigener Hook-Mechanismus (`.git/hooks/<name>`, nie versioniert). `bin/onboard` schreibt
  denselben Wrapper WIE bei `.claude/hooks/*`, nur ans andere Ziel — und **klobbert nie** einen
  bereits vorhandenen Fremd-Hook (prüft auf den eigenen Wrapper-Inhalt, schreibt nur bei
  Übereinstimmung/Fehlen). Sobald der Wrapper dort liegt, ist er SOFORT live — kein
  `settings.json`-Äquivalent, keine Stufe-C-Wartezeit.

## So fügst du einen Hook hinzu

1. **Registry-Zeile** in die Tabelle oben eintragen (Hook | Trigger | Zweck | Regel-Quelle | aktiv?).
2. Falls der Hook **beschreibende Daten** braucht: ein `team-rules/<thema>.{md,paths,…}`-File anlegen
   (deklarativ, projekt-überschreibbar). KEINE Daten im Script hardcoden.
3. **Script** unter `hooks/<name>.sh` anlegen: `dev-team.env` sourcen → `team-rules/`-Daten lesen →
   Mechanik ausführen. Den fail-safe-/stdin-Vertrag oben einhalten. `bash -n hooks/<name>.sh` prüfen.
4. **Verdrahten** passiert über `bin/onboard` (Baustein „Hook-Install") bzw. einen Projekt-Wrapper
   unter `.claude/hooks/` — NICHT manuell am Live-Projekt (das ist ein Scharfschalt-Schritt, Tier-3/human-OK).
5. Registry-Status auf ✓ setzen, sobald verdrahtet.
