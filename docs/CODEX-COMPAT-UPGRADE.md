# BobNet Codex Compatibility Upgrade

Runbook for porting or refreshing BobNet/Claude-style structure for Codex.

## Goal

Translate the existing BobNet structure to Codex-native surfaces without spawning any Bobs during
installation. Team-Bobs are created only by `init-bobs` inside a target project and only after the
user approves the proposed `TEAM.md`.

## Surface Mapping

| Claude/BobNet surface | Codex-compatible surface |
|---|---|
| `~/.claude/skills/init-bobs` | `~/.agents/skills/init-bobs` |
| `<project>/.claude/skills` | `<project>/.agents/skills` |
| `CLAUDE.md` | `AGENTS.md` |
| `.claude/hooks/*` | `.codex/hooks.json` + `.codex/hooks/*` |
| Claude Agent tool | Codex subagents: `worker`, `explorer`, custom `.codex/agents/*.toml` |
| `_dev_team/` | unchanged |
| `projects.registry.json` | unchanged, optional `"surface": "codex"` |

## Files Added For Codex

- `bin/install-codex`
  - Machine-level install.
  - Links engine skills into `~/.agents/skills`.
  - Writes `~/.codex/bobiverse.json`.

- `bin/onboard-codex`
  - Project-level structural onboarding.
  - Creates `_dev_team/`, `.agents/skills`, `.codex/agents`, `.codex/hooks.json`, hook wrappers,
    and `AGENTS.md` if absent.
  - Registers the project in `projects.registry.json`.

- `.codex-plugin/plugin.json`
  - Minimal Codex plugin manifest for local/plugin-directory experiments.

- `docs/CODEX.md`
  - Human-facing map of BobNet concepts to Codex surfaces.

- `skills/init-bobs/SKILL.md`
  - Frontmatter must be valid YAML.
  - Description should mention `/init-bobs`, `init bobs`, team setup, and Codex subagents.
  - Body should state that install/onboard only prepares structure; team agents spawn later.

## Install Flow

```bash
/path/to/claude-bobnet/bin/install-codex
```

Expected results:

```text
~/.agents/skills/init-bobs -> /path/to/claude-bobnet/skills/init-bobs
~/.codex/bobiverse.json
```

Restart Codex if the skill is not visible. Codex scans user skills from `~/.agents/skills`, not
`~/.codex/skills`.

## Project Onboard Flow

```bash
PROJECT_UID=<stable_uid> THEME=bobiverse /path/to/claude-bobnet/bin/onboard-codex <project-root>
```

Expected project structure:

```text
<project>/
├─ AGENTS.md
├─ .agents/skills/init-bobs -> <engine>/skills/init-bobs
├─ .codex/
│  ├─ agents/
│  │  ├─ bobnet-worker.toml
│  │  ├─ bobnet-explorer.toml
│  │  └─ bobnet-reviewer.toml
│  ├─ hooks.json
│  └─ hooks/
│     ├─ deploy-guard.sh
│     └─ session-heartbeat.sh
└─ _dev_team/
   ├─ dev-team.env
   ├─ memories/
   └─ standup/qa/
```

This still does not spawn Team-Bobs. It only prepares the folder so `init-bobs` has the correct
Codex-native structure.

## Validation

Run syntax checks:

```bash
bash -n bin/install-codex
bash -n bin/onboard-codex
```

Validate plugin manifest:

```bash
python3 ~/.codex/skills/.system/plugin-creator/scripts/validate_plugin.py /path/to/claude-bobnet
```

Smoke-test onboarding in `/tmp`:

```bash
rm -rf /tmp/bobnet-codex-poc
mkdir -p /tmp/bobnet-codex-poc
git init /tmp/bobnet-codex-poc
PROJECT_UID=poc_codex THEME=bobiverse bin/onboard-codex /tmp/bobnet-codex-poc
find /tmp/bobnet-codex-poc -maxdepth 4 -type f -o -type l -o -type d | sort
```

Remove the temporary registry entry afterwards:

```bash
python3 -c 'import json; p="projects.registry.json"; d=json.load(open(p)); d["projects"]=[x for x in d.get("projects",[]) if x.get("uid")!="poc_codex"]; open(p,"w").write(json.dumps(d,indent=2)+"\n")'
rm -rf /tmp/bobnet-codex-poc
```

## Gotchas

- Codex user skills live in `~/.agents/skills`.
- `~/.codex/skills` is not the documented user-skill scan location.
- Codex may not support arbitrary custom slash commands. Treat `/init-bobs` as a prompt trigger for
  the `init-bobs` skill; users can also invoke through `/skills` or `$init-bobs`.
- Do not create project folders or SSH keys as part of compatibility setup.
- Do not spawn subagents during install/onboard. Spawn only after `init-bobs` maps the repo and the
  user says `go`.
- Bash variable `UID` is readonly; use names like `REG_UID` in scripts.
- Plugin validation requires valid YAML skill frontmatter and a manifest with `author` and
  `interface` objects.

