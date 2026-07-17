# claude-bobnet

**The Bobiverse engine — Team-Lead-orchestrated AI dev teams, universal and versioned.**

Spin up a whole team of background agents for any project: one **Team-Lead** in your main
window orchestrates, reviews and merges; specialist agents own bounded slices of the repo and
report back. The structure (roles, gates, comms, process) lives in a **shared engine** so every
project — and every machine — can inherit the same battle-tested setup. Symlinked skills follow an
upgraded engine checkout; re-onboarding refreshes generated rules and wrappers, while copied
instance state remains local.

> ⚠️ **Work in progress.** The core engine (3-layer architecture, Circle-of-Trust, `init-bobs`,
> Claude Code and Codex onboarding, SCUT comms, Colonel/GUPPI checks, recycle tooling and BobNet
> dashboard) is built and in daily use — but young and evolving fast. **Expect rough edges, gaps,
> and breaking changes.** Public release policy intends `minimal` as the neutral default; current
> onboarding and dashboard fallbacks still select `bobiverse` pending alignment (see
> [Homage](#homage--origin)).

This README is meant to be read front-to-back by a newcomer. The three deep sections —
[Layers](#1-layers--the-three-schichten), [Bobs](#2-bobs--the-whole-cast) and
[Structures](#3-structures--hierarchy--processes) — explain how the engine actually works, with
real JSON, real rules and worked-through walk-throughs. Examples use the placeholder project
`acme` throughout.

---

## The concept: a Bobiverse (3 levels)

```
Bobiverse        the whole installation (root stored in the active surface's Bobiverse config)
│
├─ BobNet        Singleton · OPTIONAL · the render-hub / dashboard for ALL your teams (one instance)
├─ Colonel       Singleton · the discipline watcher (availability / processes / sync / lead heuristics)
│
└─ Project-Bobiverse  (per repo)  →  Bob#1 (Team-Lead) + SCUT + GUPPI + team agents + helpers
```

- **Bob#1** — the main window. Spawns and manages the team, owns the integration merge.
- **SCUT** — the comms layer (human ↔ BobNet ↔ services like Telegram). One per project.
- **GUPPI** — the per-project helper service: inventories processes/schedules, forwards normalized
  SCUT input and checks or self-registers the project when a BobNet appears.
- **Helpers** (ephemeral, not team-members): **ROAMER** (bounded edits), **Sonde** (read-only
  reconnaissance) and **Advisor** (read-only strategic second opinion on the `fable` model).

A **Project-Bobiverse runs fine without a BobNet** (SCUT for comms + GUPPI for process-watch are
enough). The dashboard is optional but strongly recommended — it is the single biggest reason the
workflow stays legible.

## Why / origin

The setup ran **great on one machine and miserably on another** — not because of the agents, but
because the *structures* (Circle-of-Trust, the 4-tier gates, the processes) were not shared. They
lived in one project's local files instead of in a reusable engine.

The fix: **bake the functionality into the engine and keep project state thin.** Projects link the
engine-owned skills; onboarding materializes or generates the surface-specific pieces it needs.
Upgrading the checkout plus re-onboarding refreshes those links, rules and wrappers while leaving
copied agents and instance state untouched. The target — and the design constraint — is **a full
team standing up in under two hours on any system.**

---

## 1. Layers — the three Schichten

The whole engine is built on a deliberate separation: **what a role does** (structure) is kept
apart from **what a role is called** (flavor), which is kept apart from **one concrete team in one
repo** (state). Three layers, one stable key — the archetype `id` — threading them together.

| Layer | What it holds | Where it lives | Visibility |
|---|---|---|---|
| **① Archetype** | *What* a role does — universal, versioned, theme-independent. No name, no avatar, no bio. | `archetypes/*.json` | this engine (public) |
| **② Theme** | The flavor: name, avatar, bio, i18n position labels — keyed by the stable archetype `id`. | `themes/<id>/theme.json` | engine ships `minimal`, `formal` and `bobiverse`; current code falls back to `bobiverse`, while release policy intends `minimal` |
| **③ Instance** | One concrete team in one repo: config, standup logs, memories and overrides. | `<project>/_dev_team/` | per project |

### ① Archetype — *what a role does*

An archetype is a small JSON document validated against `schemas/archetype.schema.json`. It is
**theme-independent on purpose**: it never names a persona, never picks an avatar. It describes the
*job*. Here is the real `archetypes/backend.json`:

```json
{
  "$schema": "../schemas/archetype.schema.json",
  "archetype": "backend",
  "category": "bob",
  "ring": "inner",
  "gateTier": "2-3",
  "positionShort": "Backend",
  "positionLong": "Backend / JSON-API",
  "modelTier": "HEAVEN",
  "model": "sonnet",
  "effort": "xhigh",
  "tags": ["backend", "dev", "db", "api"],
  "defaultTools": "all",
  "canSpawn": ["roamer", "sonde"],
  "areaType": "repo-bound",
  "auftrag": "Builds + maintains the backend (models, auth, FSM, migrations, seeds, API, ...). Delivers the contracts to the frontend.",
  "duties": ["Heartbeat before task start + honor Circle-of-Trust", "dev: TDD + comments (see team-rules/tags/dev.md)", "backend/api: document API contracts (CONTRACT_<feature>.md)", "db: migrations dry-run-safe + seeds idempotent"],
  "rights": ["Full dev-server authority in its own revier"],
  "idPattern": "BOB-backend"
}
```

Every field, explained:

| Field | Meaning |
|---|---|
| `archetype` | The role slug — the file's identity. |
| `category` | Taxonomy: `bob` (full team-member), `service` (daemon), `helper` (ephemeral), `coworker` (external human-driven), `human`. Drives how the dashboard classifies it. |
| `ring` | Proximity to the sprint loop — `core` / `inner` / `gate` / `outer` / `on-demand` / `shared`. Org-chart, not authority (see [Circle of Trust](#circle-of-trust--rings)). |
| `gateTier` | The Circle-of-Trust risk band this role is licensed to work in (`"1"`, `"2-3"`, `"2-4"`, …). The number that governs autonomy. See [tier system](#circle-of-trust--4-risk-tiers). |
| `tags[]` | Area/duty markers. Shared instructions live **once per tag** in `team-rules/tags/<tag>.md` — no per-agent duplication. The `dev` tag, for instance, pulls in TDD + commenting duties. |
| `model` | The concrete provider model: normally `opus` / `sonnet` / `haiku`; `fable` is the explicit Mythos-class Advisor exception, not a tier fallback. |
| `modelTier` | The human-readable model band: **HEAVEN** → `opus`, **Cruiser** → `sonnet`, **Probe** → `haiku` unless an archetype explicitly selects another model. |
| `effort` | Provider reasoning band (`low` / `medium` / `high` / `xhigh` / `max`), resolved separately from the concrete model. |
| `defaultTools` | `"all"` for builders/reviewers; a restricted list for helpers (a Sonde gets read-only tools). |
| `canSpawn[]` | Which helper/HiWi classes this role may spawn. Only the Team-Lead may spawn the HiWi + GUPPI. |
| `areaType` | `repo-bound` (owns one app dir), `cross-cutting` (spans repos), `shared` (cross-project service), `on-demand`, `external`. |
| `auftrag` | One-line mission statement. |
| `duties[]` | The standing obligations. They **begin** with the heartbeat + Circle-of-Trust line and then *reference* the tag files rather than duplicating their content. |
| `rights[]` | What the role is explicitly allowed to do (e.g. release owns the sole deploy trigger). |
| `idPattern` | The stable persona-binding key, `<CATEGORY>-<role>` (here `BOB-backend`). **This is the thread** that ties archetype → theme → instance. |

**Why theme-independent matters:** the same `backend.json` powers a buttoned-up corporate team
and a Bobiverse-flavored hobby project. Nothing about the *job* changes when the *flavor* does.

### ② Theme — *what a role is called*

A theme binds a **persona** (name / avatar / bio / i18n position label) to each archetype by its
stable `id`. It is validated against `schemas/theme.schema.json`. Switching themes changes **only
appearance** — never structure, tiers, tags, duties or routing.

The engine ships three flavors:

| Theme | Character |
|---|---|
| `minimal` | Neutral role labels, all on the default avatar. **Intended public release default; select explicitly until the executable fallbacks are aligned.** |
| `formal` | Buttoned-up corporate labels. |
| `bobiverse` | The Dennis-E.-Taylor homage — each member a lore replicant. **Current onboarding/dashboard fallback.** |

Same archetype `id`, different flavors. From `themes/minimal/theme.json`:

```json
"BOB-backend": { "name": "Backend" }
```

…and the very same key in `themes/bobiverse/theme.json`:

```json
"BOB-backend": {
  "name": "Bill",
  "avatar": "Bill.png",
  "positionLabel": { "de": "Backend + Infra", "en": "Backend + Infra" },
  "bio": { "de": "...", "en": "Bob's child, backend specialist." }
}
```

Both resolve the **same** `archetypes/backend.json` — same tier, same tags, same duties, same
model. **What the theme changes:** display name, avatar image, position label (i18n `{de,en}`),
bio. **What it can never change:** anything structural. A theme has no `gateTier`, no `tags`, no
`duties`. That separation is what makes a theme swap a cosmetic, zero-risk operation.

A theme also carries display settings and fallbacks:

- **`defaultAvatar`** — bundled themes provide one under `themes/<id>/avatars/`. If the field is
  absent, runtime uses `default.png`; if the theme image still cannot be served, the dashboard
  falls back to its static default image. Team-members are shown as an image, never an emoji.
- **`settings.showAvatars`** — image on/off; when off, the name shows (never an emoji).
- **`leadTitle`** + per-persona **`positionLabel`** are i18n `{de,en}` objects.

### ③ Instance — *one team in one repo*

The instance is the only **stateful, per-project** layer. It lives under `<project>/_dev_team/`:

```
<project>/_dev_team/
├─ dev-team.env        the instance config — PROJECT_UID (immutable), display name, theme, paths
├─ standup/            heartbeat logs (one file per agent) + _inbox.md + qa/
├─ memories/           project-local memory; the Claude memory index may link here
└─ team-rules/         OPTIONAL project overrides (win over engine defaults — except the T4 floor)
```

Surface files live beside that state: classic onboarding copy-once materializes archetypes under
`.claude/agents/`, while Codex onboarding generates `.codex/agents/*.toml`; neither is an
`_dev_team/agents/` directory.

The instance config (`dev-team.env`, abbreviated from `scripts/dev-team.env.example`):

```bash
export PROJECT_NAME="Acme Inc"     # mutable display name — may change anytime
export PROJECT_UID="acme"          # IMMUTABLE short namespace — NEVER changes
export THEME="bobiverse"           # which flavor this team wears
export DEV_TEAM_EMAIL="team@example.com"   # one shared commit email for all agents
export TEAM_LEAD="Bob"             # the inbox @-recipient / heartbeat default
export STANDUP_DIR="$HOME/.../acme/_dev_team/standup"
```

The crux: **`PROJECT_UID` is immutable** (a short namespace like `acme`) while the **display name
is mutable** (`Acme Inc`). The UID anchors branch prefixes, the registry, dashboard routing,
spawn UIDs and namespacing — so it must never drift even if the product is renamed. The display
name is free to change.

### The override chain — a worked example

Rules resolve through a strict precedence:

```
project _dev_team/team-rules/   >   BobNet house-rules   >   engine defaults
```

The most-local file wins. A worked example — a project that wants to **tighten** the migration
gate beyond the engine default:

1. **Engine default** (`team-rules/tiers.md`): T3 work needs the full circle including Compliance
   and green project gates. A staging **deploy** still needs explicit human permission per action
   unless the PO has documented a project-local autonomous-staging opt-in.
2. The Acme team is mid-audit and wants migrations to require an additional human nod before
   merge. They copy the complete tier file to `acme/_dev_team/team-rules/tiers.md`, preserve T1/T2
   and T4, and add that stricter clause to T3.
3. When the tier resolver runs with that project root, it picks the project file because it is more
   local. T1 and T2 still come from that complete project override if restated there; overrides are
   whole-file precedence, not a per-tier merge.
4. **But:** the project file may only *widen* protection. It **cannot** weaken **T4** — see the
   non-overridable floor in [Structures](#circle-of-trust--4-risk-tiers). A project file that tried
   to delete an immutable guard-floor glob is ignored for that glob; the hook merges it back in.

The same whole-file precedence applies to `heartbeat.md`, `commits.md` and `sync.md`. T4 policy
remains non-overridable; the guard machine-enforces the specific hard floors described below.

### Role resolution — how a JSON becomes a running agent

This is the whole point of the three layers — here it is, step by step, for one backend agent in
the `acme` project on the `bobiverse` theme:

1. **Pick the archetype.** `init-bobs` maps the repo's real seams to roles. The `acme_backend`
   dir → `archetypes/backend.json`.
2. **Resolve the persona.** Take the archetype's `idPattern` (`BOB-backend`), look it up in the
   active theme (`themes/bobiverse/theme.json`) → name `Bill`, avatar `Bill.png`, label
   `Backend + Infra`.
3. **Resolve the model.** This archetype selects `model: sonnet` + `effort: xhigh` explicitly even
   though its broad band is `modelTier: HEAVEN`; explicit archetype data wins the tier fallback.
   Instance overrides remain a PO cost/quality decision.
4. **Resolve the duties.** Load the archetype `duties[]`, then expand each tag in `tags[]`
   (`backend`, `dev`, `db`, `api`) by reading `team-rules/tags/<tag>.md`. The `dev` tag, for
   example, injects the TDD + commenting obligations — once, shared, not copy-pasted per agent.
5. **Resolve the tier.** `gateTier: "2-3"` → the agent loads only the T2–T3 Circle-of-Trust scope
   via `bin/tier backend` (it does not need to carry T1 or T4 context it never uses).
6. **Resolve the spawn UID.** Combine `PROJECT_UID` + role → `acme-backend-dev`. This is the
   concrete instance identity used in the BobNet, heartbeat routing and SCUT addressing.
7. **Spawn.** Bob#1 launches a background agent with that persona, revier (the exact `acme_backend`
   paths), tier scope, tools (`defaultTools: all`), guardrails, the heartbeat protocol and the
   inbox-read obligation. The agent confirms scope in 2–3 lines and awaits tasks.

The result: a running `Bill` who *is* the backend archetype, wearing the bobiverse flavor, scoped
to one repo, knowing exactly how far autonomy reaches.

---

## 2. Bobs — the whole cast

### What "a Bob" is

In this engine, **a "Bob" is a spawned full team-member instance** with a persona, a revier, a tier
and a heartbeat. The word is a flavor label (the `bobiverse` homage), not a literal name
requirement; on the `minimal` theme the same instance is just "Backend." A Bob participates in the
roster loop: it heartbeats, reads the inbox, owns work and delivers findings or branches. Spawned
helpers remain sub-units, not Bobs.

**Bob#1 is special.** It is the **Team-Lead in your main window** — the one instance that
orchestrates, plans sprints, triggers the QM gates, talks human-to-human with the PO, and owns the
integration merge. Every other Bob is a background agent it spawns and manages. Bob#1 is *not*
counted against the team-size cap (it is your window, always there).

Three things that are **not** Bobs (full team-members) but show up around the team:

- **Services** — daemons that serve the team(s): SCUT, GUPPI, Colonel. Own session, no revier.
- **Helpers** — ephemeral sub-units a Bob spawns for a slice of work: ROAMER, Sonde or Advisor. No
  roster entry; they appear only as a badge on their parent.
- **External coworkers + the human** — human-driven participants (a designer, a shared-layer
  maintainer, the PO). They contribute, but the engine does not spawn them.

### The shipped archetype catalog

Every role is a JSON file in `archetypes/`; [`archetypes/README.md`](./archetypes/README.md) is the
compact catalog. The current spawned team-role archetypes are below. Bobiverse persona names are
theme examples only; `—` means that theme has no dedicated persona binding for the role.

| Role (archetype) | Owns | Ring | Tier | Tags | Model | Bobiverse persona |
|---|---|---|---|---|---|---|
| **techlead** | Orchestration: sprint planning, gate triggering, the integration merge, human-facing comms. Sole orchestration authority. | core | 1–3 | `docs` | opus (HEAVEN) | Bob |
| **backend** | Backend models, auth, migrations, APIs and contracts. | inner | 2–3 | `backend, dev, db, api` | sonnet (HEAVEN) | Bill |
| **frontend** | App components, pages, clients and i18n. | inner | 1–2 | `frontend, js, dev, i18n` | sonnet (HEAVEN) | Luke |
| **website** | Public sites, content delivery, SEO/OG and i18n. | inner | 1–2 | `website, js, dev, i18n, seo` | sonnet (HEAVEN) | Linus |
| **design** | Component-first product and interface design. | inner | 1–2 | `design` | opus (HEAVEN) | — |
| **review** | Code-review before every merge: house-rules, correctness, i18n parity, URL↔locale, dead-link check, SEO basics. 30s mini-tick even on hotfixes. | gate | 1–3 | `review` | sonnet | Riker |
| **compliance** | Dependencies, egress, privacy, provenance and data minimization. | gate | 3 | `compliance` | sonnet (HEAVEN) | Dexter |
| **tests** | Unit/E2E coverage, project CI expectations and regression specs. | gate | 2–3 | `tests` | sonnet | Marvin |
| **release** | Pre-flight (build dry-run, asset-size, migration dry-run, visual-verify in both locales) + the deploy to staging. **Sole deploy owner.** | gate | 2–4 | `release` | sonnet | Bender |
| **dashboard** | The BobNet roster, heartbeats, tasks, roadmap and badges. | outer | 1–2 | `dashboard, js, dev` | sonnet (HEAVEN) | Garfield |
| **docs** | Periodic reports + tech docs + doc-drift detection. Keeps documentation current to the code. | outer | 1 | `docs` | sonnet | Homer |
| **content** | Lesson/product content, both locales, showcase, question payloads without solution-leaks. A specialist, not part of the builder loop. | outer | 1 | `content, i18n, dev` | sonnet | Bridget |
| **explainer** | Read-only explanations of setup, dependencies and runtime behavior from real code. | outer | 1 | `docs` | sonnet | Howard |
| **support** | User triage, reproduction, escalation and reply drafting. | outer | 1 | `docs` | sonnet | — |
| **marketing** | Campaigns, messaging, landing content and SEO/OG strategy. | outer | 1 | `content, i18n, seo` | sonnet (HEAVEN) | — |
| **hiwi** | Executes a Team-Lead-provided runbook or `PLAN_*.md` strictly; drift means stop. | on-demand | 1–3 | `dev` | haiku (Probe) | Mario |

### Services and episodic gates

These are not roster team-members. Some run as services; Plan Judge is invoked only for a bounded
decision:

| Service | Scope | What it does |
|---|---|---|
| **SCUT** | per project | Normalizes and routes external events. Telegram and email adapters are functional; GitHub and Teams remain demo stubs. Cross-installation Bridge traffic uses a separate, audited trust path. |
| **GUPPI** | per project | `guppi.sh` inventories mux/cron state, checks the registry and may re-run idempotent onboarding to self-register when BobNet appears, then passes normalized events to the existing SCUT router. It reports drift; it does not yet auto-sync or execute an open-ended chore queue. |
| **Colonel** | one per Bobiverse (singleton) | `colonel.sh` checks BobNet availability, process inventory, git sync drift and a lead-commit-ratio heuristic. Worker-idle/task-coupling heuristics remain explicit placeholders; QM-gate and forbidden-push checks are not implemented. |
| **Plan Judge** | episodic | `archetypes/plan-judge.json` provides an on-demand roadmap-alignment judgment at sprint-end, pre-merge or on drift. It never builds or merges. |

### Helpers (per-Bob, ephemeral)

Roles may spawn the helper classes listed in their archetype's `canSpawn[]` for a bounded slice of
work. Helpers carry **no roster entry** — the dashboard shows them only as a badge on the parent.
ROAMER and Sonde use `haiku`; Advisor is an intentionally expensive, read-only `fable` exception:

| Helper | Tools | Use |
|---|---|---|
| **ROAMER** 🕷️ | read + write + bash | Active worker drone: short, bounded edits — clean up, fix, build, screenshot, asset-slim, file-migrate. Spawn-on-demand, does the job, vanishes. Small = subagent; large = workflow + worktree-isolation. |
| **Sonde** 🛰️ | read-only | Read-only scout: find, read, inventory, report (where is X used, find all Y, check state). **Manipulates nothing.** For actual changes, spawn a ROAMER instead. Returns a conclusion, not file-dumps. |
| **Advisor** 🦉 | read-only | Strategic second opinion for architecture, costly decisions and hard bugs. Recommends with reasoning; implementation stays with the team. |

The Advisor's mission says a lead invokes it on demand, but the shipped `techlead.canSpawn[]`
currently omits `advisor`; treat that as a catalog/permission-contract gap, not implicit authority.

(The 🕷️/🛰️ icons are *helper-class dashboard badges*, not persona emoji — team-members are always
shown as an image, never an emoji. See the avatar rule under [Theme](#-theme--what-a-role-is-called).)

### The naming rule

A hard rule (in `CONVENTIONS.md`): **every agent, service, coworker and the human gets a
descriptive, role-based name and a stable `id` — never an opaque token** like `agent1`, `p0`,
`u1`, `bot3`. This holds even in internal comms (heartbeats, @-mentions, logs, task owners). Opaque
IDs caused real coordination failures — mis-routed tasks, broken @-mentions, confusion about *whose*
backend agent is *whose*. Descriptive names fixed that.

Two identity levels, never conflated:

| Level | Schema | Example | Scope |
|---|---|---|---|
| **Archetype / persona id** | `<CATEGORY>-<role>` | `BOB-backend` | project-independent; binds archetype ↔ theme persona |
| **Spawn UID** (instance) | `<PROJECT_UID>-<role>` | `acme-backend-dev` | one concrete instance in one project; the SCUT address token |

The `PROJECT_UID` prefix is what makes `acme-backend-dev` unambiguous vs. `other-backend-dev` when
the BobNet sees several projects at once. The dashboard hides the prefix for display (shows
"Backend") and keeps the full UID internally (collision-free).

**The Taylor homage** lives **only** in the `bobiverse` theme. The persona-to-role
mapping (e.g. `BOB-backend` → *Bill*, `BOB-techlead` → *Bob*, `BOB-tests` → *Marvin*) is purely a
flavor choice in `themes/bobiverse/theme.json`. Current executables fall back to it even though
public release policy intends `minimal`; choosing `minimal` explicitly gives the same roles neutral
names such as "Backend", "Lead" and "QA". Nothing structural depends on the homage.

---

## 3. Structures — hierarchy & processes

### The 3-level hierarchy

```
Bobiverse  ─ the whole installation on this machine (root in the Claude or Codex surface config)
   │
   ├─ BobNet   ─ Singleton, OPTIONAL ─ the dashboard/render-hub for ALL teams (one instance)
   ├─ Colonel  ─ Singleton ─ the discipline watcher across the whole installation
   │
   └─ Project-Bobiverse (one per repo)
         ├─ Bob#1   ─ Team-Lead (main window) ─ orchestrates + merges
         ├─ SCUT    ─ comms layer (one per project)
         ├─ GUPPI   ─ helper service (one per project)
         ├─ team agents ─ backend / frontend / review / tests / … (mapped to the repo's seams)
         └─ helpers ─ ROAMER / Sonde / Advisor (ephemeral, per agent)
```

- **Bobiverse** — the umbrella. One per machine; its root is recorded in the active surface config
  (`~/.claude/bobiverse.json` or `~/.codex/bobiverse.json`).
- **Singletons** — **BobNet** (the dashboard, one for all your teams, optional) and **Colonel**
  (the discipline watcher, one for the whole installation). There is exactly one of each.
- **Project-Bobiverse** — one per repo. Each has its **own** Bob#1, SCUT and GUPPI; teams are
  isolated but talk to each other over SCUT. A Project-Bobiverse runs perfectly well *without* a
  BobNet — SCUT (comms) + GUPPI (process-watch) are enough; the dashboard is the legibility
  multiplier on top.

### Circle of Trust — rings

`ring` (in each archetype) places a role by its **proximity to the sprint loop** — an org-chart of
cadence, not a chain of command:

| Ring | Who | Cadence |
|---|---|---|
| **core** | Team-Lead | Orchestrates, spawns + manages the team, holds the gates. |
| **inner** | Product builders (backend / frontend / website) | Build features in their own revier. |
| **gate** | QM (review / compliance / tests / release) | The quality gates before merge/deploy. |
| **outer** | Own cadence (docs / dashboard / content / marketing / support) | Cross-repo, asynchronous. |
| **on-demand** | Helper class (roamer / sonde / advisor) | Ephemeral, spawnable by a permitted role, **no roster entry**. |
| **shared** | Service archetypes such as GUPPI | Own session and serve a team or installation. SCUT is script-backed rather than an archetype; Colonel's current `process-auditor` JSON is in the `gate` ring. |

### Circle of Trust — 4 risk tiers

Where `ring` is org-chart, `gateTier` is **risk and autonomy**. Every agent carries one. The source
policy is [`team-rules/tiers.md`](./team-rules/tiers.md). Its short T1–T3 matrix used to say
“autonomous to staging” while its detailed action table required human permission for each staging
deployment unless the PO documented a project opt-in — that internal conflict is now fixed at the
source: the matrix follows the same stricter, action-specific rule described below.

| Tier | Required gate / control | Autonomy boundary |
|---|---|---|
| **T1 — Text / copy / brand / i18n** | Review 30s-tick + local project gate; consuming-project CI when configured | Lead autonomous through implementation and the green integration gate; staging execution follows the policy below. |
| **T2 — Feature (frontend / backend)** | Review + Tests + Release pre-flight; consuming-project CI when configured | Lead autonomous through implementation and the green integration gate; staging execution follows the policy below. |
| **T3 — Security / migration / dependencies / egress** | Full circle **incl. Compliance**; consuming-project CI when configured | Lead autonomous only after the full green integration gate; staging execution follows the policy below. |
| **T4 — Production / DNS / secrets / force-push / history rewrite / remote-branch delete** | Full gate plus explicit human control; agent actions remain denied | **Human only — hard boundary** |

By default, executing a staging deployment requires explicit human permission for that action. A
project may opt into team-autonomous staging only through a documented PO decision and a full green
circle. Projects may otherwise tighten T1–T3; **T4 can never be weakened.**

#### Machine enforcement — non-overridable BLOCK and ASK floors

The [`deploy-guard`](./hooks/deploy-guard.sh) is a data-driven `PreToolUse` hook with two immutable
path floors:

- **BLOCK** — human-only T4 paths are rejected with exit code 2.
- **ASK** — deploy-configuration edits return `permissionDecision: ask`, requiring explicit human
  confirmation for each edit. A project may promote ASK to BLOCK, but never weaken either floor.

A separate, opt-in command list can require ASK for matching deploy commands. The complete engine
default BLOCK list is broader than the immutable floor; a project BLOCK-list override replaces
those non-floor defaults. Projects cannot remove either hard floor and may promote ASK cases to
BLOCK. The path contracts live in `team-rules/deploy-guard.paths` and
`team-rules/deploy-guard.ask.paths`; command matching and its procedure live in the adjacent files.

- **Install is not activation.** Classic `bin/onboard` installs and self-tests the guard wrapper but
  does not register the `PreToolUse` hook in project settings. The guard becomes active only after
  surface-specific hook wiring is explicitly enabled. The git-native pre-push floor is different:
  Git activates it immediately when Onboard installs its executable wrapper.
- **Floors survive overrides.** `t4_floor` and `ask_floor` are always re-merged when a project
  override omits them. Projects can add or tighten protection, not subtract it.

`bin/tier <role>` prints just one role's tier scope, so an agent loads only the trust context it
actually needs (a T1 docs role never carries T4 deploy context).

### Workflow — heartbeat, inbox, gates, merge

**Heartbeat protocol.** Before *every* step, an agent appends one line via
`scripts/log.sh <Name> <state> "<what>"` (`state` ∈ `busy` / `idle` / `blocked` / `done`). The
rules live in [`team-rules/heartbeat.md`](./team-rules/heartbeat.md); the key design choices:

- **One file per agent** (`<STANDUP_DIR>/<Agent>.log`) → isolates routine heartbeats and minimizes cross-agent write conflicts.
- **Token-cheap** — the only write is one short line per step; the dashboard polls and renders.
- **Routing is data-driven.** The hook resolves `AGENT = HEARTBEAT_AGENT (if set) else TEAM_LEAD`
  and `TARGET = STANDUP_DIR` from `dev-team.env`. A normal project's lead just heartbeats as
  itself; a cross-project shared service (e.g. the dashboard agent serving another team) sets
  `HEARTBEAT_AGENT` + `STANDUP_DIR` and correctly logs *as itself into that team's BobNet*.
- **Fail-safe** — the hook never blocks a session; if `log.sh` is missing it silently `exit 0`s.

**Inbox / relay.** At every heartbeat an agent reads `standup/_inbox.md`. Same-project comms stay on
these fast local files. Messages are append-only canonical lines in the recipient's inbox; findings
return to the Team-Lead, who remains the sole editor for shared plans/backlogs. Agents never type
into another agent's terminal session.

**Watcher / delivery.** `scripts/inbox-watch.sh` is a one-shot, scheduler-friendly fleet watcher.
It wakes only idle/done or stale-busy leads, treats a new heartbeat as delivery proof, re-nudges
unverified events and then escalates by `info` / `mid` / `urgent`. An `.off-duty` flag suppresses
wakes without discarding state; session-down events escalate once per outage. Lead-authored deltas
finalize silently only when the canonical line ends exactly in `— (<lead UID or unambiguous
persona>)`; put any persona emoji before that delimiter. Server-stamped SCUT and Bridge entries are
always foreign. `tmux` is the fleet default for headless boot/nudge/recycle cycles; zellij remains
supported for interactive use.

**Measured recycle.** `bin/recycle <uid>` performs handover → kill → clean boot → fresh-heartbeat
verification. It blocks a boot while a client remains attached, purges dead zellij resurrection
state and can additionally require a fresh Claude/Codex process with the project working directory.

**The QM gate sequence.** Every FE/BE/website sprint — *including* hotfixes — runs the gates
sequentially before integration:

The engine repository ships a local black-box gate (`bash tests/run.sh`) but no hosted CI workflow.
“CI green” therefore applies only when the consuming project has CI configured.

```
Review (correctness, house-rules, i18n, dead-links)
   → Compliance (deps / egress / PII / provenance — T3+)
      → Tests (local behavior specs; consuming-project CI when present)
         → Pre-Flight (build dry-run, asset-size, migration dry-run, visual-verify both locales)
            → Merge (Team-Lead integrates)
```

The exact set depends on the tier (T1 may need only Review plus the applicable local/project gate;
T3 pulls in Compliance). The
Team-Lead **actively pings** the gate roles — it does not passively wait.

**Single-merge-owner.** Only **Bob#1 merges** into the integration branch. Specialist agents
deliver feature branches and never touch the integration branch themselves. When two agents build
on deeply-coupled code, each gets its own git worktree (`isolation: "worktree"`); broadly-separated
reviers may share the tree. This one rule is the biggest churn-preventer in the whole workflow.

### Lifecycle — install · onboard · watch · recycle · upgrade

| Command | What it does |
|---|---|
| `bin/install` | Claude Code machine bootstrap: links skills into the Claude user skill directory, writes the Claude-side Bobiverse config and runs a preflight. |
| `bin/install-codex` | Codex machine bootstrap: links skills into `~/.agents/skills`, writes `~/.codex/bobiverse.json` and runs a preflight. |
| `bin/onboard <project-root>` | Claude Code project onboarding, idempotent and non-destructive: links memory/skills, materializes absent agents, writes lifecycle/identity wrappers, attempts to install the git-native pre-push identity/content floor when the target is a Git repo and no unrelated hook exists, creates `dev-team.env`, upserts the registry and self-tests deploy-guard. |
| `bin/onboard-codex <project-root>` | Codex project onboarding: creates `_dev_team/`, `.agents/skills`, `.codex/agents`, native hook configuration and `AGENTS.md` when absent, then registers the project. |
| `scripts/inbox-watch.sh` | One watcher pass across registered projects: heartbeat-verified delivery, retry/severity handling, off-duty suppression and session-down escalation. |
| `bin/recycle <uid>` | Orderly handoff → kill → boot → verify; waits for attached clients, clears stale zellij resurrection state and can require both a heartbeat and a project-rooted agent process. |
| `bin/upgrade` | `git pull` the engine → `bin/check-compat` → classic `bin/onboard`. Codex projects currently need a separate `bin/onboard-codex` refresh after compatibility review. |
| `bin/start <uid>` | Launches the BobNet dashboard against a project. |
| `bin/tier <role>` | Prints a single role's Circle-of-Trust scope. |
| `bin/sync` | Git sync helper (`fetch` + `pull` + `push` against `origin`). |

The pre-push hook is a deliberately narrow, loudly bypassable early floor; it does not replace
Compliance or a general secret scanner. For unattended leads, `tmux` is the fleet default. Zellij
remains supported interactively but is deprecated for headless nudge/recycle cycles.

**Onboarding is bidirectional.** After the matching Claude/Codex onboard command, the project
references the engine and its instance config **and** registers with BobNet. Non-TTY onboards pass
`PROJECT_UID=<uid>` as env rather than guessing a default (the scripts exit 3 rather than silently
inventing one).

**Upgrade — referenced parts follow, instance state stays local.** Engine-owned skill links and
hook targets follow the upgraded checkout. On the classic path, re-onboarding refreshes generated
wrappers and path-scoped rules; Codex uses its separate re-onboard path noted above. Materialized
agents and project-local state (standup logs, `dev-team.env`, memories) remain untouched.
Compatibility is guarded by `VERSION` (SemVer) + `SCHEMA_VERSION` (int); `bin/check-compat` stops an
incompatible re-onboard.

### SCUT routing

SCUT normalizes inbound events from pluggable channels
(`scripts/channels/{telegram,email,github,teams}.sh`) into one shape, then `scut-router.sh` routes
them:

- **Directed** (`@X` or `[uid]`) → straight to that agent's / project's inbox.
- **Undirected** → a "someone must check" queue, so nothing silently drops.

Routing is data-driven from `projects.registry.json`; project-level defaults such as `TEAM_LEAD`
come from that project's `dev-team.env`. This is
also how two Project-Bobiverses talk: there is **no "join" skill** — joining another team's loop is
just inter-Bobiverse comms over SCUT. Register both projects with the matching onboard path and
SCUT carries cross-team pings; same-project internal comms stay on the fast local standup files.

---

## Quick start

Choose the installer for your agent surface; do not run both paths as one sequence.

### Claude Code

```bash
# First contact on a bare machine — clone anywhere; the engine resolves its
# own location (nothing is hard-wired to a fixed path):
git clone git@github.com:Litora-Nova/claude-bobnet.git
cd claude-bobnet
./bin/install
PROJECT_UID=acme ./bin/onboard /path/to/acme
```

Invoke the installed `init-bobs` skill from the target project. It maps the repo, writes a
`TEAM.md` proposal and waits for an explicit `go` before spawning the team.

### Codex

```bash
git clone git@github.com:Litora-Nova/claude-bobnet.git
cd claude-bobnet
./bin/install-codex
PROJECT_UID=acme ./bin/onboard-codex /path/to/acme
```

In Codex, invoke the skill through `/skills`, `$init-bobs` or an explicit `init-bobs` request. The
same approval boundary applies: structural onboarding does not spawn agents, and `init-bobs` stops
at `TEAM.md` until the user says `go`. See [`docs/CODEX.md`](./docs/CODEX.md) for the surface map.

On both surfaces, [`skills/init-bobs/SKILL.md`](./skills/init-bobs/SKILL.md) maps agents to the
repo's real boundaries rather than imposing a generic roster.

## The 2-hour acceptance test

On a fresh throwaway system:

1. Clone the engine and run the surface-specific installer (`bin/install` or `bin/install-codex`).
2. Run the matching project onboard command with a stable `PROJECT_UID`, then invoke `init-bobs`.
   It maps the project and stops at its approval boundary; approve the `TEAM.md` with `go`.
3. **Bob#1 + SCUT + GUPPI are running**, the BobNet at the dashboard port shows the project
   without emoji fallbacks, the configured guard wiring is active and `bin/tier <role>` returns
   each role's scope.
4. A second project gets its own Project-Bobiverse and talks to the first over SCUT.
5. On Claude Code, `bin/upgrade` pulls and re-onboards while instance state stays untouched. On
   Codex, compatibility-check the update and re-run `bin/onboard-codex`; the upgrade command's
   automatic re-onboard is not surface-aware yet.

That is the bar: **a working team in under two hours on any system.**

## Homage & origin

The concept is an affectionate **homage to Dennis E. Taylor's *Bobiverse* novels** — the in-house
`bobiverse` theme names its agents after the replicant crew, and the engine borrows the books'
ideas of a self-replicating, self-coordinating fleet (one BobNet, one Colonel, GUPPI and ephemeral
helpers). The homage is deliberate and lives only in `bobiverse`. Public release policy intends the
neutral `minimal` theme; current executable fallbacks still select `bobiverse` pending alignment.

**Read the books — seriously.** If you don't know the *Bobiverse* yet, fix that. It is the most
fun a software-minded person can have with a sci-fi series:

- 📖 **Books** — start with *We Are Legion (We Are Bob)* · [English][bk-en] · [Deutsch][bk-de]
- 🎧 **Audiobooks** — narrated by Ray Porter, an absolute joy · [English][ab-en] · [Deutsch][ab-de]

*(Those are affiliate links — a few crumbs go to this engine's author, at no extra cost to you.)*

[bk-en]: https://amzn.to/4ekwFfZ
[ab-en]: https://amzn.to/4e8tpDs
[bk-de]: https://amzn.to/3QiS5Rx
[ab-de]: https://amzn.to/43gfHcv

**Origin.** It started on **2026-05-21**, when the author first installed Claude Code after a talk
by one of its leads — skeptical, terminal-shy, expecting little. The background
"team agents" turned out to work *several times better* than going solo. A first experiment
borrowed the Bobiverse naming; the structures that made it click (Circle-of-Trust, the gates, the
processes) were then baked into this shared engine, so the good parts travel to every project
instead of living in one machine's local files. The journey also produced a Claude Code feature
request → **[anthropics/claude-code#63415](https://github.com/anthropics/claude-code/issues/63415)**.

## Repository layout

| Path | Contents |
|---|---|
| `archetypes/` | Machine-readable team roles, services, helpers, coworkers and the human role (layer ①) |
| `themes/` | Flavor layer (②): `minimal`, `formal` and the `bobiverse` homage |
| `schemas/` | Draft-07 schemas for archetypes, themes and the projects registry; a runtime `team.config` schema remains planned |
| `bin/` | Claude/Codex install and onboard, upgrade/compatibility, start, recycle, tier, sync/share and ownership queries |
| `scripts/` | Heartbeats, inbox watcher, SCUT channels/router, Bridge transport, mux/boot libraries and Colonel/GUPPI services |
| `hooks/` | Two-stage deploy guard, pre-push identity/content floor, session heartbeat, sync reminder and context trimming |
| `team-rules/` | Circle-of-Trust, tiers, tags, heartbeat, commits, sync (declarative house-rules) |
| `dashboard/` | The BobNet dashboard (Nuxt 3) |
| `skills/` | `init-bobs` for team setup and `update-bobs` for controlled engine updates |
| `.codex-plugin/` | Codex plugin manifest and distribution metadata |
| `docs/` | Codex surface mapping, compatibility runbooks and engine knowledge |
| `tests/` | Black-box behavior specs for the engine scripts |

Hard rules for the whole team OS are in [`CONVENTIONS.md`](./CONVENTIONS.md).

## Credit

Built by **Austin & the Bob's** :)

**Human in charge:** Torsten Wetzel (austin) · <austin@litora-nova.com>

**Code traces:** GitHub [2strange](https://github.com/2strange) · [twetzel](https://github.com/twetzel) · GitLab [trendgegner](https://gitlab.com/trendgegner)

Crafted at **[Litora Nova](https://litora-nova.com)**.

## License

Licensed under the **MIT License** — see [`LICENSE`](./LICENSE).
