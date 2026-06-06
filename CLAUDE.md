# claude-bobnet — working on the engine

Guidance for anyone (human or agent) working **on this engine repo itself**. For *what* the
engine is and how to use it in a project, read [`README.md`](README.md) first — it is written to
be read front-to-back. This file is the contributor/agent layer on top of it.

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
- [`team-rules/`](team-rules/) — the behavioral canon, pulled fresh into every agent's context:
  - `tiers.md` / `circle-of-trust.md` — Circle-of-Trust 4 risk tiers + rings. **T4
    (production / DNS / secrets) is a non-overridable floor, human-only.**
  - `working-style.md` · `autonomy.md` — tone, push-back, how far an agent goes alone.
  - `lessons.md` · `routines.md` · `commits.md` — accumulated lessons, standup/feierabend
    routines, commit conventions.
  - `tags/*` — per-role rule slices (backend, frontend, review, tests, docs, …).

## 4. Working on the engine

- **Tests / TDD** — the test gate lives in [`tests/`](tests/): run `bash tests/run.sh` (exit 0 =
  green, 1 = red; pass a spec name to run one). Specs are black-box behavior tests against the
  documented spec, kept separate from the scripts (**behavior > source-pattern**). New behavior →
  new/updated spec. Some scripts also expose a `--self-test` mode for a quick sanity check, but
  those are **not** counted as the gate (self-confirming).
- **Dashboard** — the BobNet render-hub lives in [`dashboard/`](dashboard/) (Nuxt; `npm run dev`
  on port 3030, `npm run build`). To launch a project's team via the hub use `bin/start <uid>`
  (a thin wrapper on the external launcher). The dashboard is optional but recommended.
- **Breaking changes** — bump `VERSION` (SemVer, for humans/changelog) and/or `SCHEMA_VERSION`
  (integer, the machine compat anchor) when you change the instance contract. Run
  `bin/check-compat` to verify engine↔instance schema compatibility before shipping a schema bump.

## 5. White-label discipline (this repo is PUBLIC)

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

## 6. Coordination model (one line)

The Team-Lead orchestrates **typed subagents that report back** to the lead, who is the
**single merge owner** — coordination comes from engine + discipline, not peer messaging. The
"Agent Teams" peer-messaging beta is an **optional** upgrade. Full rationale: [`CONVENTIONS.md`](CONVENTIONS.md) §5.
