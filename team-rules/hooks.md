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
| `deploy-guard.sh` | PreToolUse (Edit\|Write\|MultiEdit) | Blockt Edits an Deploy-/Production-/Secret-Pfaden (Tier-4, human-only). Exit 2 = Block. | `team-rules/deploy-guard.paths` (Fallback: eingebaute Defaults) | ⊘ gebaut, NICHT verdrahtet (Stufe C) |
| `session-sync-reminder.sh` | SessionStart | Rendert den State-Sync-Reminder (Branch-Check + fetch/pull/push über die Repos). | `team-rules/sync.md` (`REMINDER:`-Block) + Env `PROJECT_NAME`, `CANONICAL_BRANCH`, `DEV_TEAM_REPOS` | ⊘ gebaut, NICHT verdrahtet (Stufe C) |
| `session-heartbeat.sh` | SessionStart | Schreibt einen Heartbeat des arbeitenden Agents (`log.sh $AGENT busy session-start`) ins BobNet der Kollab-Instanz. Default-Agent = Lead; shared Services setzen `HEARTBEAT_AGENT`. Fail-safe, blockt nie. | Env `HEARTBEAT_AGENT` (Default `TEAM_LEAD`) + `STANDUP_DIR` aus `dev-team.env` + `team-rules/heartbeat.md` → `scripts/log.sh` | ⊘ gebaut, NICHT verdrahtet (Stufe C) |

**Status-Legende:** ✓ aktiv (in `.claude/settings.json` verdrahtet) · ⊘ gebaut, nicht verdrahtet · ✗ deaktiviert.

> Alle drei Hooks sind in W3 **gebaut + `bash -n`-sauber**, aber bewusst NICHT in die
> `.claude/settings.json` des Live-Projekts verdrahtet — das ist **Stufe C** (Scharfschalten,
> braucht human-OK). `bin/onboard` (Baustein 4 „Hook-Install") übernimmt die Verdrahtung beim
> Onboard eines Projekts.

## Konventionen (für jeden Hook)

- **Env zuerst:** `source` das nächstgelegene `dev-team.env` (Projekt > Engine-Default), dann die `team-rules/`-Daten.
- **Fail-safe:** SessionStart-Hooks dürfen die Session NIE blocken — bei Fehlern still `exit 0`.
  Nur `deploy-guard` darf bewusst blocken (`exit 2`), und nur bei echtem Pfad-Treffer.
- **stdin-Vertrag (PreToolUse):** Hook bekommt das Tool-JSON auf stdin. `deploy-guard` zieht den
  `file_path` jq-frei heraus (Regex), damit kein jq-Dependency nötig ist.
- **Pfad-Auflösung:** Hooks leiten ihr Engine-ROOT relativ zu `${BASH_SOURCE[0]}` ab — kein hartkodierter Pfad.
- **Daten vor Code:** Globs/Texte/Repos kommen aus `team-rules/*` bzw. Env, nie aus dem Script-Body.

## So fügst du einen Hook hinzu

1. **Registry-Zeile** in die Tabelle oben eintragen (Hook | Trigger | Zweck | Regel-Quelle | aktiv?).
2. Falls der Hook **beschreibende Daten** braucht: ein `team-rules/<thema>.{md,paths,…}`-File anlegen
   (deklarativ, projekt-überschreibbar). KEINE Daten im Script hardcoden.
3. **Script** unter `hooks/<name>.sh` anlegen: `dev-team.env` sourcen → `team-rules/`-Daten lesen →
   Mechanik ausführen. Den fail-safe-/stdin-Vertrag oben einhalten. `bash -n hooks/<name>.sh` prüfen.
4. **Verdrahten** passiert über `bin/onboard` (Baustein „Hook-Install") bzw. einen Projekt-Wrapper
   unter `.claude/hooks/` — NICHT manuell am Live-Projekt (das ist ein Scharfschalt-Schritt, Tier-3/human-OK).
5. Registry-Status auf ✓ setzen, sobald verdrahtet.
