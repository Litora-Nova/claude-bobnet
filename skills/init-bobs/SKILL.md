---
name: init-bobs
description: Stand up (or join) a project's Bobiverse — a Team-Lead-orchestrated team of background agents wired into the shared engine (Circle-of-Trust, heartbeat, registry, SCUT comms). Detects or installs the Bobiverse, onboards the project bidirectionally, interviews the user, and on approval spawns Bob#1 + SCUT + GUPPI + the team mapped to the repo's real seams. Use when the user asks to "init bobs", "set up a team", "init dev team", delegate areas to multiple agents, or orchestrate parallel agents per project.
---

# init-bobs

Stands up a **Projekt-Bobiverse**: a team where **the main window is the Team-Lead**
(Bob#1 — orchestrates, reviews, integrates, merges) and delegates bounded work to
background agents, so the main window stays responsive instead of being blocked.

The functionality lives in the **engine** (this repo); the project only *references* it
(symlinks + a small instance config). An engine update reaches every project (pull it in later with the `update-bobs` skill); the gates
(Circle-of-Trust, deploy-guard) are baked into the engine and pulled fresh at init.

> Renames + supersedes the legacy `init-dev-team` skill. The old `join-dev-team` skill is
> **retired** — joining another team is not a skill, it is inter-Bobiverse comms over SCUT
> (see *Inter-Bobiverse comms* below).

## The Bobiverse model (3 levels)

```
Bobiverse        the whole installation (root variable, stored in ~/.claude/bobiverse.json)
├─ BobNet        Singleton · OPTIONAL · the render-hub/dashboard for ALL teams (one instance)
├─ Colonel       Singleton · the discipline watcher (processes / BobNet-sync / lead-orchestrates)
└─ Projekt-Bobiverse (per folder)  →  Bob#1 (Team-Lead) + SCUT + GUPPI + team-bobs + helpers
```

- **Bob#1** = the main window: spawns + manages the team, owns merges.
- **SCUT** = the comms layer (human ↔ BobNet ↔ services: Telegram, …) — one per Projekt-Bobiverse.
- **GUPPI** = the helper service (process/schedule watch, routes SCUT inputs, BobNet-register check).
- **Helpers** (per bob, not team-members, dashboard icon-only): ROAMER (simple edits), Sonde
  (simple searches), Jeeves (1 per bob, the more-capable executor).

## Hard rules

- **Ask inline, in the chat. NEVER use the `AskUserQuestion` dialog box** — the user disabled it.
- **Plan before building.** Produce `TEAM.md`, get an explicit "go" before onboarding/spawning.
- **Never (re)start dev servers** — the user does that. Bake this into every agent's guardrails.
- **One owner per path.** No two agents own or edit the same files; never run two agents in the
  same app concurrently (worktree-isolate or sequence instead).
- **Spec / Backlog = single source of truth**, edited only via the Team-Lead.
- **Map to THIS repo's real seams** — read the repo first; don't impose a generic roster.
- **Circle-of-Trust is non-negotiable.** Every agent gets a `gateTier` (T1–T4); **T4 is a
  non-overridable floor** (`.secrets/`, `master.key`, `credentials.yml.enc`, `*.env.production`).
  The `deploy-guard` hook enforces T4 from minute 1 (onboard runs a self-test).
- **Commit-authorship:** agents commit under their persona, not a placeholder. Engine convention
  lives in `team-rules/commits.md` (`Co-Authored-By: <Name> (<Projekt-Display> <role>)
  <team-email>`); never set the repo's static `user.*` to one agent (overwrites everyone).

### Coordination rules (lessons that pay off)

- **Single-merge-owner:** only Bob#1 merges into the integration branch; agents deliver feature
  branches and never touch it themselves.
- **Worktree per agent when coupling is deep:** two agents building on the same code each get
  their own git worktree (`isolation: "worktree"`). Broad, separated reviers may share the tree.
- **"Report when done", not mid-flight pings:** fewer status pings; honest `blocked` when waiting.

### Quality gate — production-ready, not just green tests

- **Pre-flight feasibility:** before any deploy/irreversible step, the Team-Lead walks the path —
  where does each artifact come from on the *target*? Is a shared layer/sibling-`extends` present
  (it is NOT on the deploy host)? Two minutes here saves hours.
- **Definition of Done = real command, real env:** frontend → real `NODE_ENV=production` build;
  backend → boot under the target runtime + migrate a fresh DB. Not "config loads".
- **House-rules checklist + link-check + shared-layer-is-a-real-dependency** — carried from the
  battle-tested QM playbook; the reviewer ticks it every gate.

## Procedure

### 0. Bobiverse check & install
- Read `~/.claude/bobiverse.json`. **Exists** (points at an engine) → continue. **Missing** →
  bootstrap: run the engine's `bin/install` (machine-global, idempotent — symlinks skills into
  `~/.claude/skills`, writes `bobiverse.json`). First contact on a bare machine is
  `git clone <engine> && <engine>/bin/install`.
- **BobNet is optional** (strongly recommended). If the user wants the dashboard, set
  `bobnet` in `bobiverse.json` and start it (`bin/start <uid>`); otherwise the Projekt-Bobiverse
  runs on SCUT + GUPPI alone, and GUPPI periodically checks whether a BobNet has appeared.

### 1. Understand the project
- Read the root `CLAUDE.md` and any `BACKLOG.md` / `MVP_SPEC.md` / docs.
- Detect the app subdirectories and whether each is its **own git repo** (root `.gitignore` often
  ignores `/<app>/` because each is a separate GitLab project; the root repo versions only
  cross-stack docs & infra).
- Identify the real boundaries: backend(s), frontend(s), infra, marketing, shared layer/reference apps.

### 2. Onboard the project (bidirectional registration)
- Run `bin/onboard <project-root>`. It is idempotent + non-destructive and does, in one pass:
  memory-symlink · skills-symlink (→ engine) · agents from `archetypes/` (only if absent) ·
  hook wrappers (deploy-guard etc. + a **git-identity export wrapper**:
  `.claude/hooks/git-identity.sh` → `scripts/git-identity.sh export`; **no `settings.json`
  touch** — arming SessionStart is Stufe-C / human-OK) · `dev-team.env` (asks/【inherits】`PROJECT_UID` — immutable; `PROJECT_NAME` =
  mutable display) · **registry upsert** into the central `projects.registry.json` ·
  deploy-guard self-test.
- **Non-TTY spawn (background agent): pass `PROJECT_UID=<uid>` as env** — `bin/onboard` cannot
  prompt without a TTY and exits 3 rather than guessing (no silent default).
- This is the **bidirectional link**: the project now references the Bobiverse (symlinks +
  `bobiverse.json` + `dev-team.env`) **and** the BobNet registers the project (registry) — so
  comms work both ways.
- **External coworker (designer/marketing on a `{HUMAN}` device)?** Set up a file-sync share for
  the project (`bin/sync-share <root> --uid <uid> --name "<Display>"`, see `team-rules/comms.md`
  §6) and drop a filled-in copy of `skills/init-bobs/templates/SYNCTHING_COWORKER.template.md`
  into the project's `share/` — it then syncs itself to the coworker.

### 3. Interview the user (inline, plain chat)
- **Cap** on number of agents (Bob#1 = main window, not counted).
- **Theme:** `bobiverse` / `formal` / `minimal` (persona names + positions come from the theme's
  `theme.json`; drives commit-authorship + dashboard display).
- **Work model:** shared tree partitioned by app (default) vs worktrees.
- **Focus vs paused:** which stacks/areas are in scope now, which are parked.
- **Roles** they want — offer the archetype palette below; add/cut to the cap.
- **New dirs** (e.g. a marketing site): own repo or monorepo subdir? which tech?
- **Style/design references** for frontend work (shared layer, exemplar apps, color/preference docs).
- **Comms:** Telegram/other via SCUT? who is the human (`{HUMAN}`) on the back-channel?
- **Multiplexer (tmux/zellij):** **auto-detect, then confirm.** Probe what's installed — offer
  **zellij** if present (incl. user-scope `~/.local/bin/zellij`), else **tmux** — show the detected
  choice and let the user accept (Enter) or override by typing the other. Write the result as
  `BOBNET_MUX=tmux|zellij` into `dev-team.env`. Daemons + dashboard read it via `scripts/lib/mux.sh`;
  if left unset the engine falls back to `auto` (tmux-preferred, for backward-compat).

### 4. Propose a roster mapped to the repo
**Keep names stable across projects** (same role → same persona every time). Always include the
three per-project singletons; pick a subset of the rest to fit the cap, each bound to a directory.
Archetypes live in `archetypes/*.json` (id, role, tags, `gateTier`, model, duties):

- **SCUT** + **GUPPI** — mandatory per Projekt-Bobiverse (comms + helper service).
- **Backend-Dev** — API/server dir (folds in DevOps/Infra if no separate slot).
- **Frontend-Dev** — client dir (folds in Design unless a separate designer is wanted).
- **Code-Reviewer** — correctness / idiomatic / style; read-mostly; gates merges.
- **Compliance/Audit** — data-minimization, new deps (SBOM), egress, audit-log, PII. Keep
  separate when the project's ethos is auditability.
- **QA/Tests** — test suites; green-gate before merge.
- **Website/Marketing** — landing page; keeps feature docs current.
- **Release/QM** — owns deploy configs end-to-end **and** the quality gate (real-path build +
  deploy dry-run, link-check, house-rules). Single owner — coupled deploy config is the churn trap.
- **Docs/Tech-Writer**, **Content** — separate slots only if the cap allows.

Present as a table: `# | Agent | Revier (paths) | gateTier | Aufgabe`. Add the Bob#1 loop,
the conflict rules, the guardrails, and each agent's `bin/tier <role>` scope.

### 5. Design/style guardrails (frontend & marketing agents)
- Prefer the framework's components (e.g. Vuetify) and current idioms, not decade-old CSS helpers.
- Check the shared layer / reference apps **before** building from scratch.
- **On design / color / layout decisions, ask** — propose with a short rationale, never decide silently.

### 6. Write TEAM.md (repo root or `_dev_team/`)
Document: work model + paused stacks, the roster table (with tiers), the Bob#1 loop, the conflict
+ coordination rules, the guardrails, the style references, the heartbeat/inbox protocol, the
Circle-of-Trust pointer (`team-rules/circle-of-trust.md` + `bin/tier`), and any new-app notes.
This is the durable contract every agent reads. **Stop here until the user says go.**

### 7. On "go": stand up the Projekt-Bobiverse
- Spawn **Bob#1** (the main window already is it) and the team agents from their archetypes with
  the **Agent tool**, `run_in_background: true`. Code-writers/reviewers = full-tool agents;
  read-only `Explore`/Sonde only for pure research.
- Onboard each in its prompt: identity (persona from theme), **revier (exact paths)**, `gateTier`,
  guardrails, references, the **heartbeat protocol** (one `standup/log.sh <Name> <state> "<what>"`
  line before each step), the **inbox** (`read standup/_inbox.md at every heartbeat`), and:
  "read `TEAM.md` + your dir's `CLAUDE.md`, confirm scope in 2–3 lines, make NO changes, await
  tasks from the Team-Lead." Set the expectation that **constructive dissent is welcome**.
- If a planned dir does not exist yet, spawn that agent in standby/research mode (study the
  reference apps), not file creation.
- **Model + effort per role (#36):** when spawning each agent, resolve its model + reasoning-effort
  from the archetype via `scripts/lib/model.sh <archetype-id>` (→ `<model> <effort>`) and pass them
  to the spawn. Precedence: instance override
  (`BOBNET_MODEL_OVERRIDE`/`BOBNET_EFFORT_OVERRIDE` / team.config) → provider-specific config
  `providers.<BOBNET_PROVIDER>` → top-level `model`/`effort` → `modelTier`. The default provider is `claude`.
  Set `BOBNET_PROVIDER=devin|codex|cursor` to spawn with another AI tool (see `scripts/lib/spawn.sh`).
  **Devin special case:** the Devin CLI has no reliable headless tool-execution mode; `--permission-mode bypass`
  fails without a TTY and hangs on complex tasks. For non-interactive Devin spawns, use the Devin subagent
  (`run_subagent`) with a task generated by `scripts/lib/spawn.sh --subagent-task devin <archetype> <start_cmd>`.

### 8. Run the loop
- Break work into **app-scoped tasks**; assign via `TaskCreate` + `TaskUpdate(owner=…)` / `SendMessage`.
- **Merge gate:** Code-Reviewer (correctness) + Compliance (audit) + QA (green) before integrating.
- Bob#1 integrates and resolves cross-app coordination; Website/Docs update after merge.
- Shut down teammates with `SendMessage({type: "shutdown_request"})` when work is done.

## Inter-Bobiverse comms (replaces `join-dev-team`)

Two Projekt-Bobiverses talk via **SCUT**, not via a join-skill. Directed messages (`@X` / `[uid]`)
route to the target Bobiverse's inbox; undirected ones land in a "someone-must-check" queue. The
routing table is data-driven from `projects.registry.json` + each team's `team.config`. To "join"
another team's loop, register both projects (each runs `init-bobs`/`onboard`) and let SCUT carry
the cross-team pings. Same-project internal comms (standup files) stays as-is — fast and proven.
