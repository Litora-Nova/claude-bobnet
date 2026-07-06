# Codex PoC

This file tracks the Codex translation of the BobNet/Bobiverse structure.

## Principle

Do not spawn Bobs during installation. Installation only makes the engine visible to Codex and
prepares the project structure. The real Team-Bobs are created by `init-bobs` in a target folder
after the user approves the proposed `TEAM.md`.

## Surface Map

| BobNet concept | Codex surface |
|---|---|
| User-visible workflow | Skill under `~/.agents/skills/init-bobs` |
| Repo-visible workflow | Skill link under `<project>/.agents/skills/init-bobs` |
| Durable project instructions | `AGENTS.md` |
| Team-Bob templates | `.codex/agents/*.toml` |
| Lifecycle guards | `.codex/hooks.json` and `.codex/hooks/*` |
| Shared instance state | `_dev_team/` |
| Dashboard registry | `projects.registry.json` with optional `"surface": "codex"` |

## Commands

```bash
# Machine-level Codex install
/path/to/engine/bin/install-codex

# Project-level structural onboarding
PROJECT_UID=<uid> /path/to/engine/bin/onboard-codex <project-root>
```

In Codex, `/init-bobs` should be treated as an explicit request to use the `init-bobs` skill.
Codex may expose the skill through `/skills` or `$init-bobs` rather than a custom slash command.
