# claude-bobnet — working on the engine

Guidance for anyone (human or agent) working **on this engine repo itself**. For *what* the
engine is and how to use it in a project, read [`README.md`](README.md) first — it is written to
be read front-to-back. This file is the **small always-on core**; subsystem-specific guidance
loads on demand (see §6).

> This file is **not** the instance identity (who runs a given team). That lives in the instance
> layer (`<project>/_dev_team/`), never in this public engine.

## 1. What this is

The **Bobiverse engine** — a shared, versioned setup for Team-Lead-orchestrated AI dev teams (see
[`README.md`](README.md)). **Status: work in progress** — built and in daily use, but young and
fast-moving. Expect rough edges and breaking changes.

## 2. The 3-layer model — know which layer you are touching

The engine deliberately separates *what a role does* from *what it is called* from *one concrete
team*. Before editing, identify the layer (full walk-through in [`README.md`](README.md), §1):

1. **Archetype** (`archetypes/*.json`, validated against `schemas/archetype.schema.json`) — *what*
   a role does. Universal, versioned, theme-independent. No name, no avatar, no bio.
2. **Theme** (`themes/<id>/theme.json`, default `minimal`) — the flavor: name, avatar, bio, i18n
   position labels, keyed by the stable archetype `id`. A theme switch changes only the look, never
   the structure.
3. **Instance** (`<project>/_dev_team/`) — one concrete team in one repo. **Not part of this
   engine** and must never be committed here.

Rule of thumb: **structure/behavior change → archetype** · **look/labels → theme** · **project
state → instance (elsewhere).**

## 3. Hard rules — reference, do not duplicate

The binding rules live in their own files; honor them, do not copy them into code or restate them
here. The canonical sources:

- [`CONVENTIONS.md`](CONVENTIONS.md) — descriptive names & IDs (never opaque tokens like `agent1`),
  avatar = image / no-emoji, sync = Git (push is part of sync), and the **coordination model (§5)**.
- [`team-rules/`](team-rules/) — the behavioral canon (referenced on demand, not all loaded every
  session):
  - `tiers.md` / `circle-of-trust.md` — Circle-of-Trust 4 risk tiers + rings. **T4
    (production / DNS / secrets) is a non-overridable floor, human-only** — machine-enforced by
    `hooks/deploy-guard.sh`, not just prose.
  - `working-style.md` · `autonomy.md` — tone, push-back, how far an agent goes alone.
  - `lessons.md` · `routines.md` · `commits.md` — accumulated lessons, standup/feierabend
    routines, commit conventions.
  - `tags/*` — per-role rule slices (backend, frontend, review, tests, docs, …).

## 4. White-label discipline (this repo is PUBLIC)

This engine ships publicly and white-label. Keep it that way:

- **No real names, no infrastructure, no internal codenames, no hostnames** — not in code, docs,
  examples, or commit messages.
- Use **`acme`** as the example project UID (as the README does) and neutral placeholders
  everywhere.
- Default release theme is **`minimal`**; any persona-flavored theme is an **optional flavor**, not
  the engine's identity. Do not bake a specific persona into archetypes, schemas, or scripts.
- **Documented exception — README credits (PO decision 2026-06-06):** the Product Owner may
  *deliberately* name themselves (and their public profiles) in the README credits block.
  Self-attribution is the PO's call, not a leak — the compliance gate marks exactly those
  credit lines as ACCEPTED instead of failing them. The exception covers **only** the PO's
  own self-mention in the credits; it extends to no other person, file, or identifier.

## 5. Coordination model (one line)

The Team-Lead orchestrates **typed subagents that report back** to the lead, who is the
**single merge owner** — coordination comes from engine + discipline, not peer messaging. The
"Agent Teams" peer-messaging beta is an **optional** upgrade. Full rationale: [`CONVENTIONS.md`](CONVENTIONS.md) §5.

## 6. On-demand rules — the engine eats its own diet

Subsystem-specific contributor guidance is **not** in this always-on core. It lives in
[`.claude/rules/`](.claude/rules/) as **path-scoped rules** that load **only when you work in that
area** (native Claude Code `paths:` frontmatter — lazy, not every session):

- `tests.md` (`tests/**`) — the test gate / TDD flow.
- `dashboard.md` (`dashboard/**`) — the BobNet render-hub (Nuxt).
- `contract.md` (`schemas/**`, `archetypes/**`, `VERSION`, `SCHEMA_VERSION`) — breaking-change /
  compat discipline.

This dogfoods the **“small always-on core · everything else on-demand”** principle (issue #34).
New subsystem guidance → a path-scoped rule, not more core prose.
