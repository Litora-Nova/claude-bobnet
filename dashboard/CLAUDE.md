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
  stand-up directory) and `server/routes/theme-avatar/[name].get.ts` (theme-aware
  avatar delivery). No database, no runtime external deps — the source is purely the
  per-agent heartbeat logs plus a few Markdown files in the stand-up directory.

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
  theme: `NUXT_THEME` > `team.config.theme` > engine default. Switching themes changes
  only appearance, never structure — and **never** introduces an emoji avatar.

Relevant `NUXT_*` env (all optional, sensible defaults):

| Env | Purpose | Default |
|---|---|---|
| `NUXT_STANDUP_DIR` | Where the per-agent `<Agent>.log` files + Markdown live | `../standup` |
| `NUXT_TEAM_CONFIG` | Explicit path to `team.config.json` | `<standupDir>/team.config.json` |
| `NUXT_THEME` | Active theme id | `team.config.theme` |
| `NUXT_THEMES_DIR` | Where theme folders live | `../themes` |
| `NUXT_ARCHETYPES_DIR` | Where archetype JSON lives | `../archetypes` |
| `NUXT_ALLOWED_HOSTS` | Extra Vite-allowed hosts (comma-separated) | — |

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
