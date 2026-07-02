---
name: update-bobs
description: Update a project's Bobiverse to the latest engine — pull the engine (ff-only), check schema compatibility, re-onboard the project idempotently (refreshes symlinked mechanics + hook wrappers, never touches instance state), then brief the active Bobs on what changed. Use when the user asks to "update bobs", "upgrade bobs", "update the engine/dev team", "refresh the bobiverse", or after an engine release landed.
---

# update-bobs

Brings **this project's Bobiverse** to the current engine and tells the team what changed.
Counterpart to `init-bobs`: *init* stands the team up once, *update* keeps it current.

The mechanics live in the engine — this skill orchestrates **`bin/upgrade`**, which does:

1. Engine `git pull --ff-only` (no merge/rebase/force — ever)
2. `bin/check-compat` — engine `SCHEMA_VERSION` vs the instance's `ENGINE_SCHEMA` (breaking skew → stop)
3. Idempotent re-onboard — refreshes what is *referenced* (symlinks: skills/memory/team-rules)
   and *generated* (hook wrappers); leaves *copy-once* (`agents/*`) and **instance state**
   (`_dev_team/standup`, `dev-team.env`, memories) **guaranteed untouched**

## Flow

**0. Locate.** Project root = walk up from cwd until a `_dev_team/` directory is found (no
`_dev_team` → this project has no Bobiverse yet; point the user to `init-bobs` and stop).
Engine root = `engine` path in `~/.claude/bobiverse.json`; fallback: resolve one of the
project's engine symlinks (e.g. `readlink -f` on the skills/team-rules link).

**1. Preflight.** Capture the before-state — you need it for the report:
- engine `VERSION`, `SCHEMA_VERSION`, `git -C <engine> rev-parse HEAD`
- instance `ENGINE_SCHEMA` from `_dev_team/dev-team.env`
- engine working tree dirty? → **stop and say so** (the pull would fail); a dirty engine tree
  is the engine maintainer's business, never stash or reset it from here.

**2. Run** `<engine>/bin/upgrade <project-root>` and show its output.

**3. Handle the exit code honestly:**
- **0** — continue to the report.
- **1** — engine pull failed (diverged branch / offline). Show `git -C <engine> status -sb`;
  do **not** force anything — hand the divergence to the engine maintainer.
- **5** — schema skew, re-onboard was intentionally skipped. Read the engine `CHANGELOG.md`
  for the migration notes between the two schema numbers, present the steps, and get an
  explicit go before migrating anything.

**4. Report.** `git -C <engine> log --oneline <old-head>..HEAD` — summarize the pulled changes
in plain language, grouped by area (archetypes / team-rules / scripts / hooks / dashboard),
plus the version jump (`vX → vY`). No commit-hash dumps; say what changed for *this team*.

**5. Brief the Bobs.** If the upgrade pulled anything, append a short note to the project's
inbox so running sessions and the next boot pick it up — resolve `STANDUP_DIR` from
`_dev_team/dev-team.env` (fallback `<project-root>/standup`), then **append** (never
overwrite — shared file) to `$STANDUP_DIR/_inbox.md`:

```
<YYYY-MM-DD HH:MM> | @<TEAM_LEAD> | 🔄 Engine-Update vX→vY (update-bobs): <2-3 key changes,
plain language>. <Action needed, if any — e.g. "new archetype available", "hook behavior changed">.
```

**6. Dashboard note (if applicable).** If the pulled commits touched `dashboard/**` and a
dashboard service runs from this engine, tell the user that the running instance still serves
the old build — rebuild + restart is a separate, human-approved deploy step. Do **not**
restart services yourself.

## Multi-project mode (only on explicit ask)

If the user explicitly asks to update **all** projects ("update all bobs"), iterate the
registered projects (the hub's `projects.registry.json`), run steps 1–5 per project, and
give one consolidated report. The engine pull happens once; per-project work is
check-compat + re-onboard + brief. Never do this implicitly.

## Hard rules

- **ff-only is the law.** Never merge, rebase, or force-pull the engine from this skill.
- **Instance state is sacred**: `_dev_team/standup`, `dev-team.env`, `agents/*`, memories —
  if an upgrade would touch them, something is wrong; stop and report.
- **Ask inline, in the chat. NEVER use the `AskUserQuestion` dialog box.**
- **Never (re)start dev servers or services** — report, and let the human deploy.
- Exit-code honesty: a failed pull or schema skew is a *result*, not an error to paper over —
  report it exactly as it happened.
