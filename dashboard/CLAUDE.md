# Dashboard — Agent-Onboarding

The **BobNet dashboard component**: a lean Nuxt 3 live dashboard that renders, in
real time, what every agent on a Team-Lead-orchestrated agent team is doing. It is
the render-hub of the engine. This file is agent guidance for working *inside* this
component; the user-facing overview lives in [`README.md`](./README.md) — keep the
two consistent.

## Stack

- **Nuxt 3** (SSR) · TypeScript · **no UI library** — hand-rolled CSS (dark palette)
  in `assets/css/main.css`.
- **Icons via `@nuxt/icon` + `mdi`**, bundled (`icon.clientBundle.icons` in
  `nuxt.config.ts`, `svg` mode). No CDN fetch, no runtime egress — **add new icon
  names to that list or they will not render.**
- **Node 24** · `npm` (no pnpm/yarn).
- **Multi-page:** `app.vue` = shell (`<NuxtLayout><NuxtPage/>`), `layouts/default.vue`
  = header-nav + footer, `pages/*.vue` = one route each. Shared live data + central
  polling: `composables/useLive.ts`.
- **Server routes:** `server/api/*.ts` (read the heartbeat logs + Markdown from the
  stand-up directory; tenant-scoped — see below), `server/api/projects.get.ts` (the
  tenant-neutral fleet view), `server/routes/theme-avatar/[name].get.ts` (theme-aware
  avatar delivery) and `server/routes/manifest.webmanifest.get.ts` (dynamic PWA
  manifest). No database, no runtime external deps — the source is purely the
  per-agent heartbeat logs plus a few Markdown files in the stand-up directory.
- **Tenant layer:** `server/utils/tenant.ts` (resolve a request to a project),
  `server/utils/registry.mjs` (read `projects.registry.json`), `server/utils/team.ts`
  (`teamOf(tenant)`), `server/utils/theme.ts` (`themeOf(tenant, team)`),
  `server/utils/activity.mjs` (the project activity rollup). See **Multi-tenant** below.

## Three display classes (HARD: avatars are always an image)

The dashboard renders an entity in one of three places, driven by its archetype
`category` (overridable per instance — never hardcoded):

| Class | Who | Rendering |
|---|---|---|
| **Roster** | Team members (`category: bob`) | Card with **image avatar**, name, role, status pill (`components/RosterCard.vue`). |
| **Service** | Cross-project daemons (`category: service`) | Compact pill showing **alive / dead** instead of the full status scale — a daemon either runs or is down (`components/ServiceStatus.vue`). "alive" = a fresh heartbeat within the alive window. |
| **Helper** | Ephemeral helpers (`category: helper`) | Icon-only **badge** on the parent agent's card — helpers are not roster entries (`components/HelperBadge.vue`). The status colors the badge dot. |

Status colors for roster/helpers: `busy` · `idle` · `blocked` · `done`.

### NO-EMOJI — hard rule (team members are NEVER an emoji)

**Team-member avatars are ALWAYS an image, NEVER an emoji** — not even as a fallback
or an option. This is enforced in code, not by convention:

- `server/utils/theme.ts` has **no `emoji` field** at all (the `Persona` type is
  `name` / `avatar` / `bio` / `positionLabel`). `avatarFileOf()` **always** returns a
  filename — the persona's `avatar` or the theme's `defaultAvatar` (`default.png`, an
  anonymous mask) — so the dashboard can never fall back to a glyph.
- The avatar route (`theme-avatar/[name].get.ts`) is two-stage: `persona.avatar` →
  theme `defaultAvatar` → 404; on 404 the client `<img @error>` falls back to the
  static `public/avatars/default.png`. At no point is an emoji rendered.
- `RosterCard.vue` / `ServiceStatus.vue` both load `/theme-avatar/<name>` and fall
  back to the static default image on error — image-only end to end.
- **Helper badges are the only glyphs**, and they are **mdi icons keyed to the helper
  *type*** (`mdi:spider`, `mdi:satellite-variant`, generic `mdi:robot-outline`) — UI
  iconography like the rest of the dashboard's mdi icons, **not** a member rendered as
  an emoji. Do not confuse the two: type-icons are fine, member-as-emoji is forbidden.

When touching any rendering path, keep this invariant. Image or static default —
never a glyph for a member.

## Config-driven (engine stays generic)

Nothing about the concrete team is hardcoded — the specifics live in the project
instance:

- **`team.config.json`** — title, Product-Owner, and the member list (each member
  keyed by a stable archetype `id`, with `role`, `order`, `groups`, optional
  `category`/`parent` overrides). Located via `NUXT_TEAM_CONFIG`, or as
  `team.config.json` inside the stand-up directory. See
  [`team.config.example.json`](./team.config.example.json).
- **`archetypes/*.json`** — supply each `id`'s default display `category` (read from
  the engine's archetype layer; `NUXT_ARCHETYPES_DIR` to relocate).
- **Themes** — name / avatar / bio per persona, keyed by the same stable `id`. Active
  theme depends on the mode (see **Multi-tenant**): tenant mode chains `registry theme`
  > `team.config.theme` > engine default; env mode chains `NUXT_THEME` >
  `team.config.theme` > engine default. Switching themes changes only appearance, never
  structure — and **never** introduces an emoji avatar.

Relevant `NUXT_*` env (all optional, sensible defaults):

| Env | Purpose | Default |
|---|---|---|
| `NUXT_STANDUP_DIR` | Where the per-agent `<Agent>.log` files + Markdown live (env mode) | `../standup` |
| `NUXT_TEAM_CONFIG` | Explicit path to `team.config.json` (env mode) | `<standupDir>/team.config.json` |
| `NUXT_THEME` | Active theme id (env mode only — ignored in tenant mode) | `team.config.theme` |
| `NUXT_THEMES_DIR` | Where theme folders live (one dir for all tenants) | `../themes` |
| `NUXT_ARCHETYPES_DIR` | Where archetype JSON lives | `../archetypes` |
| `NUXT_REGISTRY` | Explicit path to `projects.registry.json` | `<cwd>/../../projects.registry.json` |
| `NUXT_ACTIVITY_WORKING_MIN` | Minutes a `busy` beat counts as **working** | `10` |
| `NUXT_ACTIVITY_RUNNING_MIN` | Minutes any beat keeps a project **running** | `60` |
| `NUXT_TMUX_PROBE` | `1` opts into the multiplexer session-name probe (off by default) | — |
| `BOBNET_MUX` | Which multiplexer the probe queries: `tmux` \| `zellij` \| `auto` (auto = tmux if present, else zellij) | `auto` |
| `NUXT_ALLOWED_HOSTS` | Extra Vite-allowed hosts (comma-separated) | — |

## Multi-tenant (one hub, many project Bobiverses)

The dashboard serves **one project at a time per request**, but can host the whole
fleet from a single instance. Every API request is resolved to a tenant by
`tenantOf(event)` (`server/utils/tenant.ts`):

- **Tenant mode** — request carries `?project=<uid>` → the entry is looked up in
  `projects.registry.json` and supplies `standup` dir, `theme`, `label`, `icon`,
  `responsibility`. Unknown `uid` → **404** (never a silent fallback onto another
  team).
- **Env mode (backward-compatible)** — **no** `?project` param → exactly the previous
  single-tenant behavior from `NUXT_STANDUP_DIR` / `NUXT_TEAM_CONFIG`. A project run
  without a registry keeps working unchanged.

The `uid` is the immutable namespace (registry rule); names/personas are display only.
Registry, team config and theme are each **mtime-cached** — projects can (de)register
and edit configs without restarting the always-on hub, but without a read per request.

- **Registry** (`server/utils/registry.mjs`) — path resolution `NUXT_REGISTRY` >
  `<cwd>/../../projects.registry.json` (the hub runs in `<engine>/dashboard`, the
  registry sits next to the engine — same resolution as `bin/start`). `projectByUid`
  matches on `uid`, falling back to `name` only while an entry has no `uid` yet.
- **Theme priority** (`server/utils/theme.ts`, `themeIdOf`) — tenant mode: `registry
  theme` > `team.config.theme` > `bobiverse`; **`NUXT_THEME` is ignored in tenant
  mode** (it would force one theme on every tenant). Env mode unchanged: `NUXT_THEME`
  > `team.config.theme` > `bobiverse`.

### Fleet view — `/bobiverse` + `/api/projects`

`pages/bobiverse.vue` (nav `mdi:orbit`) stacks **all** registered projects with each
one's activity status and its latest heartbeats (a cross-project view — you see who is
working in parallel). `/api/projects` is deliberately **tenant-neutral** (the fleet,
not the active project). A click switches the dashboard onto that team **without a
restart**: it sets the `bobnet-project` cookie (`composables/useProject.ts`) and the
live fetches in `composables/useLive.ts` re-query the same stable keys against the new
tenant (`useProjectQuery()` is reactive on the cookie).

### Activity semantics (`server/utils/activity.mjs`)

Pure functions (kept `.mjs` so they are node-testable). Per agent, from heartbeat
freshness: **working** (fresh `busy` ≤ `workingMin`) · **running** (any beat ≤
`runningMin`, session present but no fresh work) · **idle** (only `idle`/`done` or
stale). The project rollup adds **registered** (project known, no logs yet).
**`blocked`** is a sticky special status: a `blocked` last beat stays prominent and
age-independent (urgent-jump) until resolved — it must not get lost in the four-step
scale. Thresholds are `NUXT_ACTIVITY_WORKING_MIN` (10) / `NUXT_ACTIVITY_RUNNING_MIN`
(60). The optional multiplexer probe (`NUXT_TMUX_PROBE=1`, opt-in) lifts a project to
at least `running` when a session name contains the project's `uid`/`name` (a
heuristic; heartbeat-only is the portable default). Which multiplexer is queried is
chosen by `BOBNET_MUX` (`tmux` | `zellij` | `auto`, default `auto` = tmux if present,
else zellij) — the same backend-selection convention as `scripts/lib/mux.sh`,
mirrored in the Node layer (the dashboard can't source the bash adapter). The probe
helpers (`resolveMuxBackend`, `muxListPlan`, `parseSessionList`) live in
`server/utils/activity.mjs`; for `zellij` it runs `zellij list-sessions
--no-formatting --short` and falls back to `~/.local/bin/zellij` (zellij is often
user-scope and missing from the Node/cron PATH).

### Dynamic manifest

`server/routes/manifest.webmanifest.get.ts` replaces the old static
`public/manifest.webmanifest`: it reads the active tenant from the `bobnet-project`
cookie (env tenant if absent) and serves a per-tenant `name` / `short_name`
(`team.config` title, falling back to the tenant label, finally `'BobNet'`). Icons /
colors / display are unchanged. It is sent `Cache-Control: private` (tenant-dependent,
must not be shared across users).

### Registry `icon` field

Each registry entry may carry an optional `icon` (a web URL or path) shown next to the
project in the fleet view; without it the UI falls back to the project's initial label.
(Favicon auto-discovery is the follow-up in issue #21.)

## Heartbeat-fed (one file per agent → no write conflicts)

1. Each agent appends `YYYY-MM-DD HH:MM | status | message` to **its own** log via the
   engine's `log.sh` helper (`<status>` ∈ `busy | idle | blocked | done`). One file per
   agent means there are **no write conflicts** — no shared file to corrupt, no locking.
   The old `HH:MM | …` form stays parse-compatible.
- The only write per step is that one line — token-cheap. The dashboard polls and
   renders; no database, no runtime egress.
2. The server route reads the stand-up directory, takes the **last 3** lines per agent,
   enriches them with the active theme's display name / avatar / bio, and returns JSON.
3. The pages poll on an interval and render the roster, service strip, helper badges,
   plus sprint goals (from an optional `_sprint.md`).

## Run

```bash
# Via the engine launcher (resolves the project by its PROJECT_UID):
bin/start <uid>          # e.g. bin/start acme

# Or directly in this directory:
npm install
npm run dev      # → http://localhost:3030
npm run build    # production build
npm run preview  # serve the production build
```

Port is fixed to **3030** (`nuxt.config.ts` `devServer`). The dashboard is internal
tooling and serves `noindex` — it is not a public site.

## Conventions

- **Avatars:** `public/avatars/default.png` is the only avatar shipped here — the
  image-only fallback (anonymous mask). Per-persona avatars live in the **theme**
  (`themes/<theme>/avatars/`), keyed by stable `id`, not in this component.
- **Compact HTML/Vue tags** on a single line; short TS files; comments may be in the
  team's working language.
- Add new mdi icons to `nuxt.config.ts` `icon.clientBundle.icons` before using them.
