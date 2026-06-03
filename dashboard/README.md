# BobNet Dashboard

A lean **Nuxt 3** live dashboard that shows, in real time, what every agent on a
Team-Lead-orchestrated agent team is currently doing. It is the render-hub of the
engine — the single biggest reason the workflow stays legible.

## What it is

- **Heartbeat-fed.** Every agent appends one short line to **its own** log file
  before each step. One file per agent means there are **no write conflicts** — no
  shared file to corrupt, no locking.
- **Token-cheap.** The only write per step is that one line. The dashboard polls
  and renders; there is no database and no runtime egress — the source is purely the
  heartbeat logs plus a few Markdown files in the stand-up directory.
- **SSR Nuxt 3, no UI library.** Hand-rolled CSS (dark palette), icons via
  `@nuxt/icon` + `mdi` (bundled, no CDN fetch). Multi-page: each area is its own
  linkable route.

## Three display classes

The dashboard renders an entity in one of three places, driven by its archetype
`category` (overridable per instance — never hardcoded):

| Class | Who | Rendering |
|---|---|---|
| **Roster** | Team members (`category: bob`) | Card with **image avatar**, name, role, status pill. Avatars are **always an image, never an emoji** — if the theme avatar fails to load, a static default image (anonymous mask) is shown. |
| **Service** | Cross-project daemons — SCUT / GUPPI / Colonel (`category: service`) | Compact pill showing **alive / dead** (a service either runs or is down) rather than the full status scale. "alive" = a fresh heartbeat within the alive window. |
| **Helper** | Ephemeral helpers — ROAMER / Sonde / Jeeves (`category: helper`) | Icon-only **badge** rendered on the parent agent's card (helpers are not roster entries). The status colors the badge dot. |

Status colors for roster/helpers: `busy` · `idle` · `blocked` · `done`.

## Config-driven

Nothing about the concrete team is hardcoded — the engine stays generic, the
specifics live in the project instance:

- **`team.config.json`** — title, Product-Owner, and the member list (each member
  keyed by a stable archetype `id`, with `role`, `order`, `groups`, optional
  `category`/`parent` overrides). Located via `NUXT_TEAM_CONFIG`, or as
  `team.config.json` inside the stand-up directory. See
  [`team.config.example.json`](./team.config.example.json).
- **`archetypes/*.json`** — supply each `id`'s default display `category`
  (read from the engine's archetype layer; `NUXT_ARCHETYPES_DIR` to relocate).
- **Themes** — name/avatar/bio per persona, keyed by the same stable `id`. Active
  theme: `NUXT_THEME` > `team.config.theme` > engine default. Switching themes
  changes only appearance, never structure.

Relevant `NUXT_*` env (all optional, sensible defaults):

| Env | Purpose | Default |
|---|---|---|
| `NUXT_STANDUP_DIR` | Where the per-agent `<Agent>.log` files + Markdown live | `../standup` |
| `NUXT_TEAM_CONFIG` | Explicit path to `team.config.json` | `<standupDir>/team.config.json` |
| `NUXT_THEME` | Active theme id | `team.config.theme` |
| `NUXT_THEMES_DIR` | Where theme folders live | `../themes` |
| `NUXT_ARCHETYPES_DIR` | Where archetype JSON lives | `../archetypes` |
| `NUXT_ALLOWED_HOSTS` | Extra Vite-allowed hosts (comma-separated) | — |

## How it works

1. Each agent appends `YYYY-MM-DD HH:MM | status | message` to its own log via the
   engine's `log.sh` helper (`<status>` ∈ `busy | idle | blocked | done`).
2. The server route reads the stand-up directory, takes the **last 3** lines per
   agent, enriches them with the active theme's display name/avatar/bio, and returns
   JSON.
3. The pages poll on an interval and render the roster, service strip, helper badges,
   plus sprint goals (from an optional `_sprint.md`).

## Run

```bash
# Via the engine launcher (resolves the project by its PROJECT_UID):
bin/start <uid>

# Or directly in this directory:
npm install
npm run dev      # → http://localhost:3030
npm run build    # production build
```

> The dashboard is internal tooling and serves `noindex`.
