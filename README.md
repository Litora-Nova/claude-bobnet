# claude-bobnet

**The Bobiverse engine — Team-Lead-orchestrated AI dev teams, universal and versioned.**

Spin up a whole team of background agents for any project: one **Team-Lead** in your main
window orchestrates, reviews and merges; specialist agents own bounded slices of the repo and
report back. The structure (roles, gates, comms, process) lives in a **shared engine** so every
project — and every machine — inherits the same battle-tested setup. An engine update reaches
every team at once.

> ⚠️ **Work in progress.** The engine (3-layer architecture, Circle-of-Trust, `init-bobs`,
> install/upgrade, SCUT comms, Colonel/GUPPI governance, BobNet dashboard) is built and in daily
> use — but young and evolving fast. **Expect rough edges, gaps, and breaking changes.** Default
> release theme is `minimal`; the in-house `bobiverse` flavor is a Dennis-E.-Taylor homage
> (see [Homage](#homage--origin)).

This README is meant to be read front-to-back by a newcomer. The three deep sections —
[Layers](#1-layers--the-three-schichten), [Bobs](#2-bobs--the-whole-cast) and
[Structures](#3-structures--hierarchy--processes) — explain how the engine actually works, with
real JSON, real rules and worked-through walk-throughs. Examples use the placeholder project
`acme` throughout.

---

## The concept: a Bobiverse (3 levels)

```
Bobiverse        the whole installation (root is configurable, stored in ~/.claude/bobiverse.json)
│
├─ BobNet        Singleton · OPTIONAL · the render-hub / dashboard for ALL your teams (one instance)
├─ Colonel       Singleton · the discipline watcher (processes / sync / lead-orchestrates)
│
└─ Project-Bobiverse  (per repo)  →  Bob#1 (Team-Lead) + SCUT + GUPPI + team agents + helpers
```

- **Bob#1** — the main window. Spawns and manages the team, owns the integration merge.
- **SCUT** — the comms layer (human ↔ BobNet ↔ services like Telegram). One per project.
- **GUPPI** — the per-project helper service: watches processes/schedules, routes incoming
  messages, checks whether a BobNet has appeared yet.
- **Helpers** (per agent, not team-members — dashboard icon only): **ROAMER** (simple edits),
  **Sonde** (read-only searches), **Jeeves** (one per agent, the more-capable executor).

A **Project-Bobiverse runs fine without a BobNet** (SCUT for comms + GUPPI for process-watch are
enough). The dashboard is optional but strongly recommended — it is the single biggest reason the
workflow stays legible.

## Why / origin

The setup ran **great on one machine and miserably on another** — not because of the agents, but
because the *structures* (Circle-of-Trust, the 4-tier gates, the processes) were not shared. They
lived in one project's local files instead of in a reusable engine.

The fix: **bake the functionality into the engine, have each project merely reference it.** Gates
are pulled fresh at init; an engine update propagates to everyone. The target — and the design
constraint — is **a full team standing up in under two hours on any system.**

---

## 1. Layers — the three Schichten

The whole engine is built on a deliberate separation: **what a role does** (structure) is kept
apart from **what a role is called** (flavor), which is kept apart from **one concrete team in one
repo** (state). Three layers, one stable key — the archetype `id` — threading them together.

| Layer | What it holds | Where it lives | Visibility |
|---|---|---|---|
| **① Archetype** | *What* a role does — universal, versioned, theme-independent. No name, no avatar, no bio. | `archetypes/*.json` | this engine (public) |
| **② Theme** | The flavor: name, avatar, bio, i18n position labels — keyed by the stable archetype `id`. | `themes/<id>/theme.json` | engine ships `minimal` / `formal`; private flavors live in your BobNet instance |
| **③ Instance** | One concrete team in one repo: agents, standup logs, `dev-team.env`, memories. | `<project>/_dev_team/` | per project |

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
  "modelTier": "Cruiser",
  "model": "sonnet",
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
| `model` | The concrete provider model (machine-resolution of `modelTier`): `opus` / `sonnet` / `haiku`. |
| `modelTier` | The human-readable model band: **HEAVEN** → `opus`, **Cruiser** → `sonnet`, **Probe** → `haiku`. |
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
| `minimal` | Neutral role labels, all on the default avatar. **The release default** — what a fresh install gets. |
| `formal` | Buttoned-up corporate labels. |
| `bobiverse` | The Dennis-E.-Taylor homage — each member a lore replicant. The private in-house flavor. |

Same archetype `id`, two flavors. From `themes/minimal/theme.json`:

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

A theme also carries a few engine-enforced settings:

- **`defaultAvatar`** — every theme **must** ship one (`themes/<id>/avatars/default.png`). A persona
  with no avatar falls back to it. (Team-members are **always** shown as an image, **never** an
  emoji — a hard rule; if you want emoji faces, build your own theme.)
- **`settings.showAvatars`** — image on/off; when off, the name shows (never an emoji).
- **`leadTitle`** + per-persona **`positionLabel`** are i18n `{de,en}` objects.

### ③ Instance — *one team in one repo*

The instance is the only **stateful, per-project** layer. It lives under `<project>/_dev_team/`:

```
<project>/_dev_team/
├─ dev-team.env        the instance config — PROJECT_UID (immutable), display name, theme, paths
├─ agents/             the spawned agents, materialized from the archetypes at onboard time
├─ standup/            heartbeat logs (one file per agent) + _inbox.md + qa/
├─ memories/           project memory, symlinked to the engine where shared
└─ team-rules/         OPTIONAL project overrides (win over engine defaults — except the T4 floor)
```

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

The most-local file wins. A worked example — a project that wants to **tighten** the staging
autonomy for migrations:

1. **Engine default** (`team-rules/tiers.md`): *T3 — Security / Migration / Dependencies. Gate:
   full circle incl. Compliance, CI green. → Team-Lead autonomous up to staging after green.*
2. The Acme team is mid-audit and wants migrations to also require an explicit human nod, even on
   staging. They drop a file at `acme/_dev_team/team-rules/tiers.md` that re-states T3 with the
   added clause *"…and a human ack in `#migrations` before merge."*
3. At init / on every read, the resolver picks the project file for T3 because it is more local.
   T1, T2 still come from the engine (no project file overriding them).
4. **But:** the project file may only *widen* protection. It **cannot** weaken **T4** — see the
   non-overridable floor in [Structures](#circle-of-trust--4-risk-tiers). A project file that tried
   to delete a T4 core glob is ignored for that glob; the engine merges it back in.

The same pattern applies to `heartbeat.md`, `commits.md`, `sync.md`: engine ships a default,
project may override, T4 is the one thing nobody can override.

### Role resolution — how a JSON becomes a running agent

This is the whole point of the three layers — here it is, step by step, for one backend agent in
the `acme` project on the `bobiverse` theme:

1. **Pick the archetype.** `init-bobs` maps the repo's real seams to roles. The `acme_backend`
   dir → `archetypes/backend.json`.
2. **Resolve the persona.** Take the archetype's `idPattern` (`BOB-backend`), look it up in the
   active theme (`themes/bobiverse/theme.json`) → name `Bill`, avatar `Bill.png`, label
   `Backend + Infra`.
3. **Resolve the model.** `modelTier: Cruiser` → `model: sonnet`. (Instance/theme may override for
   cost/quality tuning — that is a PO call.)
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

In this engine, **a "Bob" is any spawned, interacting instance** — a full team member with a
persona, a revier, a tier and a heartbeat. The word is a flavor label (the `bobiverse` homage), not
a literal name requirement; on the `minimal` theme the same instance is just "Backend." What makes
something *a Bob* is that it participates in the loop: it heartbeats, reads the inbox, owns work,
delivers branches.

**Bob#1 is special.** It is the **Team-Lead in your main window** — the one instance that
orchestrates, plans sprints, triggers the QM gates, talks human-to-human with the PO, and owns the
integration merge. Every other Bob is a background agent it spawns and manages. Bob#1 is *not*
counted against the team-size cap (it is your window, always there).

Three things that are **not** Bobs (full team-members) but show up around the team:

- **Services** — daemons that serve the team(s): SCUT, GUPPI, Colonel. Own session, no revier.
- **Helpers** — ephemeral sub-units a Bob spawns for a slice of work: ROAMER, Sonde, Jeeves. No
  roster entry; they appear only as a badge on their parent.
- **External coworkers + the human** — human-driven participants (a designer, a shared-layer
  maintainer, the PO). They contribute, but the engine does not spawn them.

### The full role palette

Every role is a JSON file in `archetypes/`. Below is the complete cast (the bobiverse-theme persona
names are shown only as an example of the flavor layer — on `minimal` they are neutral labels).

| Role (archetype) | Owns | Ring | Tier | Tags | Model | Bobiverse persona |
|---|---|---|---|---|---|---|
| **techlead** | Orchestration: sprint planning, gate triggering, the integration merge, human-facing comms. Sole orchestration authority. | core | 1–3 | `docs` | opus (HEAVEN) | Bob |
| **backend** | Backend app dir: models, auth, FSM, migrations, seeds, API, compliance endpoints. Delivers contracts to frontend. | inner | 2–3 | `backend, dev, db, api` | sonnet | Bill |
| **frontend** | App frontend (SPA): components, pages, composables, API clients, i18n. Consumes the backend contracts. | inner | 1–2 | `frontend, js, dev, i18n` | sonnet | Luke |
| **website** | Public marketing sites: content, SEO, OG, i18n. No CMS, no tracking. | inner | 1–2 | `website, js, dev, i18n, seo` | sonnet | Linus |
| **review** | Code-review before every merge: house-rules, correctness, i18n parity, URL↔locale, dead-link check, SEO basics. 30s mini-tick even on hotfixes. | gate | 1–3 | `review` | sonnet | Riker |
| **compliance** | New deps / lockfile touches / egress / PII / tokens-in-logs / asset provenance / data-minimization. Every lockfile touch auto-pings this role. | gate | 3 | `compliance` | sonnet | Marvin |
| **tests** | Test coverage: unit + E2E, CI coverage floor, title-specs per page in both locales, composable unit tests. Pings *before* merge on missing specs. | gate | 2–3 | `tests` | sonnet | Dexter |
| **release** | Pre-flight (build dry-run, asset-size, migration dry-run, visual-verify in both locales) + the deploy to staging. **Sole deploy owner.** | gate | 2–4 | `release` | sonnet | Bender |
| **dashboard** | The live stand-up dashboard (BobNet): roster, heartbeats, tasks, roadmap, badges. Cross-project service, own cadence. | outer | 1–2 | `dashboard, js, dev` | sonnet | Garfield |
| **docs** | Periodic reports + tech docs + doc-drift detection. Keeps documentation current to the code. | outer | 1 | `docs` | sonnet | Homer |
| **content** | Lesson/product content, both locales, showcase, question payloads without solution-leaks. A specialist, not part of the builder loop. | outer | 1 | `content, i18n, dev` | sonnet | Bridget |
| **support** | First contact for real users: triage, reproduce, escalate to the right role, draft replies. Activates from first real users. | outer | 1 | `docs` | sonnet | Howard |
| **marketing** | Campaigns, messaging, landing content, SEO/OG strategy, naming proposals. Own cadence. | outer | 1 | `content, i18n, seo` | sonnet | (planned) |
| **hiwi** | Executes a Team-Lead-handed `PLAN_*.md` **strictly**, no improvisation. For cases where plan-drift would be expensive (layer/layout/deploy/stack-critical). Drift = STOP. | on-demand | 1–3 | `dev` | sonnet | Mario |

### Services (daemons)

These run as their own sessions and serve the team(s) — they are not roster team-members:

| Service | Scope | What it does |
|---|---|---|
| **SCUT** | per project | The channel-pluggable comms layer (human ↔ BobNet ↔ external channels). Normalizes incoming events and routes them; carries cross-Bobiverse pings. Telegram live today, others stubbed. |
| **GUPPI** | per project | Judgment-free routine executor (`archetypes/guppi.json`, model `haiku`): process/schedule watch, recurring non-dev chores, auto-sync of `_dev_team`, and the "has a BobNet appeared yet?" check. **On drift it escalates to the Team-Lead — it never guesses.** |
| **Colonel** | one per Bobiverse (singleton) | The discipline watcher (`archetypes/process-auditor.json`, persona *Colonel Butterworth*): is the BobNet up and in sync, are there orphaned processes, is the lead *orchestrating* rather than doing busywork, did the QM gates actually run, were there forbidden pushes. Mechanical, judgment-light; reports `✓` / `⚠` / `✗` and escalates process drift. |

### Helpers (per-Bob, ephemeral)

Any Bob can spawn helpers for a bounded slice of work. They carry **no roster entry** — the
dashboard shows them only as a badge on the parent agent. All run on the cheap `haiku` model:

| Helper | Tools | Use |
|---|---|---|
| **ROAMER** 🕷️ | read + write + bash | Active worker drone: short, bounded edits — clean up, fix, build, screenshot, asset-slim, file-migrate. Spawn-on-demand, does the job, vanishes. Small = subagent; large = workflow + worktree-isolation. |
| **Sonde** 🛰️ | read-only | Read-only scout: find, read, inventory, report (where is X used, find all Y, check state). **Manipulates nothing.** For actual changes, spawn a ROAMER instead. Returns a conclusion, not file-dumps. |
| **Jeeves** | full | The more-capable executor — **one per Bob** — for heavier delegated work than a ROAMER. |

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

**The Taylor homage** lives **only** in the optional `bobiverse` theme. The persona-to-role
mapping (e.g. `BOB-backend` → *Bill*, `BOB-techlead` → *Bob*, `BOB-tests` → *Dexter*) is purely a
flavor choice in `themes/bobiverse/theme.json`; the default `minimal` theme is neutral and names
the same roles "Backend", "Lead", "QA". Nothing structural depends on the homage.

---

## 3. Structures — hierarchy & processes

### The 3-level hierarchy

```
Bobiverse  ─ the whole installation on this machine (root in ~/.claude/bobiverse.json)
   │
   ├─ BobNet   ─ Singleton, OPTIONAL ─ the dashboard/render-hub for ALL teams (one instance)
   ├─ Colonel  ─ Singleton ─ the discipline watcher across the whole installation
   │
   └─ Project-Bobiverse (one per repo)
         ├─ Bob#1   ─ Team-Lead (main window) ─ orchestrates + merges
         ├─ SCUT    ─ comms layer (one per project)
         ├─ GUPPI   ─ helper service (one per project)
         ├─ team agents ─ backend / frontend / review / tests / … (mapped to the repo's seams)
         └─ helpers ─ ROAMER / Sonde / Jeeves (ephemeral, per agent)
```

- **Bobiverse** — the umbrella. One per machine; its root is recorded in `~/.claude/bobiverse.json`.
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
| **on-demand** | Helper class (roamer / sonde / Jeeves) | Ephemeral, spawnable by any member, **no roster entry**. |
| **shared** | Cross-project services (GUPPI / SCUT / Colonel) | Own session, serve several teams. |

### Circle of Trust — 4 risk tiers

Where `ring` is org-chart, `gateTier` is **risk and autonomy**. Every agent carries one. The tiers
decide how far the Team-Lead may go autonomously (canonical text in
[`team-rules/tiers.md`](./team-rules/tiers.md)):

| Tier | Gates exactly | Autonomy boundary |
|---|---|---|
| **T1 — Text / copy / brand / i18n** | Review 30s-tick + CI green | Team-Lead, autonomous up to staging |
| **T2 — Feature (frontend / backend)** | Review + Tests + Release pre-flight, CI green | Team-Lead, autonomous up to staging |
| **T3 — Security / migration / dependencies / egress** | Full circle **incl. Compliance**, CI green | Team-Lead, autonomous up to staging **after green** |
| **T4 — Production / DNS / secrets** | Everything + **explicit human OK** | **Human only — hard boundary** |

**T1–T3 are project-adjustable** via the override chain (a project can *tighten* them). **T4 is
not.**

#### The T4 floor — non-overridable, machine-enforced

T4 is the one hard line. A project override may only **widen** protection, never remove the core
globs. Those globs are declared in [`team-rules/deploy-guard.paths`](./team-rules/deploy-guard.paths)
(data, not code — extend protection by appending a line, no code edit needed). The protected core:

```
*/config/deploy.rb      */config/deploy/*      *Capfile      *configuration.yml
*/.secrets/*            *credentials.yml.enc    *master.key   *.env.production
*/nginx/*production*    *docker-compose.prod*   */k8s/production/*
```

The [`deploy-guard`](./hooks/deploy-guard.sh) hook is the **machine enforcement** of T4. It is a
`PreToolUse` hook: when any `Edit` / `Write` / `MultiEdit` targets one of these globs, the hook
**blocks with exit code 2** and prints why — no agent, not even Bob#1, can touch a production /
deploy / secret path. Two properties make it trustworthy:

- **Armed from minute one.** The onboard step runs a `deploy-guard` self-test, so the floor is live
  before the first task runs — not a thing you remember to switch on later.
- **The floor re-merges even against a hostile override.** The hook merges the T4 core globs back
  in (its `t4_floor` function) even if a project's override file tries to omit them. You can add
  protection; you cannot subtract the core.

`bin/tier <role>` prints just one role's tier scope, so an agent loads only the trust context it
actually needs (a T1 docs role never carries T4 deploy context).

### Workflow — heartbeat, inbox, gates, merge

**Heartbeat protocol.** Before *every* step, an agent appends one line via
`scripts/log.sh <Name> <state> "<what>"` (`state` ∈ `busy` / `idle` / `blocked` / `done`). The
rules live in [`team-rules/heartbeat.md`](./team-rules/heartbeat.md); the key design choices:

- **One file per agent** (`<STANDUP_DIR>/<Agent>.log`) → no write conflicts, ever.
- **Token-cheap** — the only write is one short line per step; the dashboard polls and renders.
- **Routing is data-driven.** The hook resolves `AGENT = HEARTBEAT_AGENT (if set) else TEAM_LEAD`
  and `TARGET = STANDUP_DIR` from `dev-team.env`. A normal project's lead just heartbeats as
  itself; a cross-project shared service (e.g. the dashboard agent serving another team) sets
  `HEARTBEAT_AGENT` + `STANDUP_DIR` and correctly logs *as itself into that team's BobNet*.
- **Fail-safe** — the hook never blocks a session; if `log.sh` is missing it silently `exit 0`s.

**Inbox / relay.** At every heartbeat an agent reads `standup/_inbox.md`. Same-project comms stay on
these fast local standup files. The **Team-Lead routes** — agents do not edit shared files directly;
findings go back to the Team-Lead, who maintains the central files (this avoids an append-loop
content-collapse that bit the team once and had to be git-recovered).

**The QM gate sequence.** Every FE/BE/website sprint — *including* hotfixes — runs the gates
sequentially before integration:

```
Review (correctness, house-rules, i18n, dead-links)
   → Compliance (deps / egress / PII / provenance — T3+)
      → Tests (coverage floor, specs for every new path, both locales)
         → Pre-Flight (build dry-run, asset-size, migration dry-run, visual-verify both locales)
            → Merge (Team-Lead integrates)
```

The exact set depends on the tier (T1 may need only Review + CI; T3 pulls in Compliance). The
Team-Lead **actively pings** the gate roles — it does not passively wait.

**Single-merge-owner.** Only **Bob#1 merges** into the integration branch. Specialist agents
deliver feature branches and never touch the integration branch themselves. When two agents build
on deeply-coupled code, each gets its own git worktree (`isolation: "worktree"`); broadly-separated
reviers may share the tree. This one rule is the biggest churn-preventer in the whole workflow.

### Lifecycle — install · onboard · upgrade

| Command | What it does |
|---|---|
| `bin/install` | Machine bootstrap (idempotent). Symlinks each skill into `~/.claude/skills`, writes `~/.claude/bobiverse.json`, runs a preflight. |
| `bin/onboard <project-root>` | Per-project, idempotent + **non-destructive**: memory + skills symlinks, agents materialized from archetypes (only if absent), hook wrappers (deploy-guard + git-identity), `dev-team.env` (asks for the immutable `PROJECT_UID`), registry upsert, deploy-guard self-test. |
| `bin/upgrade` | `git pull` the engine → `bin/check-compat` → idempotent re-onboard. |
| `bin/start <uid>` | Launches the BobNet dashboard against a project. |
| `bin/tier <role>` | Prints a single role's Circle-of-Trust scope. |
| `bin/sync` | Git sync helper (`fetch` + `pull` + `push` against `origin`). |

**Onboarding is bidirectional.** After `bin/onboard`, the project *references* the Bobiverse
(symlinks + `bobiverse.json` + `dev-team.env`) **and** the BobNet *registers* the project (registry
upsert) — so comms work both ways. Non-TTY (background-agent) onboards pass `PROJECT_UID=<uid>` as
env rather than guessing a default (the script exits 3 rather than silently inventing one).

**Upgrade — referenced parts propagate, instance state is untouched.** The engine's *referenced*
parts (skills, memory, team-rules — all symlinked) update **instantly** on `bin/upgrade`. The
*copied* parts (the materialized agents) and all instance state (standup logs, `dev-team.env`,
memories) are **left alone**. Compatibility is guarded by `VERSION` (SemVer) + `SCHEMA_VERSION`
(int); `bin/check-compat` catches a breaking skew before it bites. That is how one engine update
reaches every team without disturbing any team's running state.

### SCUT routing

SCUT normalizes inbound events from pluggable channels
(`scripts/channels/{telegram,email,github,teams}.sh`) into one shape, then `scut-router.sh` routes
them:

- **Directed** (`@X` or `[uid]`) → straight to that agent's / project's inbox.
- **Undirected** → a "someone must check" queue, so nothing silently drops.

The routing table is data-driven from `projects.registry.json` + each team's `team.config`. This is
also how two Project-Bobiverses talk: there is **no "join" skill** — joining another team's loop is
just inter-Bobiverse comms over SCUT. Register both projects (each runs `init-bobs` / `onboard`) and
SCUT carries the cross-team pings; same-project internal comms stay on the fast local standup files.

---

## Quick start

```bash
# First contact on a bare machine — clone anywhere; the engine resolves its
# own location (nothing is hard-wired to a fixed path):
git clone git@github.com:Litora-Nova/claude-bobnet.git
cd claude-bobnet
./bin/install                              # machine-global, idempotent

# Then, in any project, from your Team-Lead window:
#   run the `init-bobs` skill — it detects/installs the Bobiverse, onboards the
#   project bidirectionally, interviews you, writes a TEAM.md plan, and on your
#   explicit "go" spawns Bob#1 + SCUT + GUPPI + the team mapped to the repo's seams.
```

`init-bobs` ([`skills/init-bobs/SKILL.md`](./skills/init-bobs/SKILL.md)) maps agents to *your*
repo's real boundaries (it reads the repo first — no generic roster imposed), stops at a `TEAM.md`
plan for approval, and only then stands up the team.

## The 2-hour acceptance test

On a fresh throwaway system:

1. `git clone` the engine → `bin/install`.
2. Run `init-bobs` in an empty folder — Bobiverse-detect installs an optional BobNet, asks for
   `PROJECT_UID`, runs the interview.
3. **Bob#1 + SCUT + GUPPI are running**, the BobNet at the dashboard port shows the project
   (image-only), `deploy-guard` is armed from minute one, `bin/tier <role>` returns each role's
   scope.
4. A second project gets its own Project-Bobiverse and talks to the first over SCUT.
5. `bin/upgrade` pulls an engine update that propagates while instance state stays untouched.

That is the bar: **a working team in under two hours on any system.**

## Homage & origin

The concept is an affectionate **homage to Dennis E. Taylor's *Bobiverse* novels** — the in-house
`bobiverse` theme names its agents after the replicant crew, and the engine borrows the books'
ideas of a self-replicating, self-coordinating fleet (one BobNet, one Colonel, GUPPI and Jeeves
as each Bob's helpers). The homage is deliberate and lives only in the optional `bobiverse` theme;
the default release theme (`minimal`) is neutral.

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
by Boris (the Claude Code lead) — skeptical, terminal-shy, expecting little. The background
"team agents" turned out to work *several times better* than going solo. A first experiment
borrowed the Bobiverse naming; the structures that made it click (Circle-of-Trust, the gates, the
processes) were then baked into this shared engine, so the good parts travel to every project
instead of living in one machine's local files. The journey also produced a Claude Code feature
request → **[anthropics/claude-code#63415](https://github.com/anthropics/claude-code/issues/63415)**.

## Repository layout

| Path | Contents |
|---|---|
| `archetypes/` | Role definitions (layer ①) + JSON schema |
| `themes/` | Flavor layer (②): `minimal` (release default), `formal`, `bobiverse` (homage) |
| `schemas/` | `archetype` + `theme` schemas, frontmatter specs |
| `bin/` | `install` · `onboard` · `upgrade` · `check-compat` · `start` · `tier` · `sync` |
| `scripts/` | `log.sh`, `scut*.sh`, `colonel.sh`, `guppi.sh`, `git-identity.sh`, channel adapters |
| `hooks/` | `deploy-guard.sh` (T4 enforcement), session heartbeat + sync-reminder |
| `team-rules/` | Circle-of-Trust, tiers, tags, heartbeat, commits, sync (declarative house-rules) |
| `dashboard/` | The BobNet dashboard (Nuxt 3) |
| `skills/init-bobs/` | The one skill that stands up a Project-Bobiverse |
| `tests/` | Black-box behavior specs for the engine scripts |

Hard rules for the whole team OS are in [`CONVENTIONS.md`](./CONVENTIONS.md).

## Credit

Built by **Austin & the Bob's** :)

**Human in charge:** Torsten Wetzel (austin) · <austin@litora-nova.com>

**Code traces:** GitHub [2strange](https://github.com/2strange) · [twetzel](https://github.com/twetzel) · GitLab [trendgegner](https://gitlab.com/trendgegner)

Crafted at **[Litora Nova](https://litora-nova.com)**.

## License

Licensed under the **MIT License** — see [`LICENSE`](./LICENSE).
