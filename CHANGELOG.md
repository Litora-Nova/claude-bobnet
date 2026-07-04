# Changelog

All notable engine changes are documented here. Versioning follows SemVer (`VERSION`,
human-facing); machine compatibility is anchored separately by `SCHEMA_VERSION` (integer) —
see `.claude/rules/contract.md`. `skills/update-bobs` points teams here after an update.

## [0.7.0] — 2026-07-04

### Added
- **Email channel goes functional** (`scripts/channels/email.sh`, was a stub): IMAP readonly
  poll feeding the existing `scut-router.sh` (registry-driven inbox-first routing, review
  queue for undirected mail). UID+UIDVALIDITY offset dedupe; addressing via subject tag
  `[<uid>]@<Agent>` or plus-address; first run anchors the offset instead of flooding old
  mail (`SCUT_MAIL_BACKFILL=1` to deliver from scratch). Attachments are counted, not
  stored (v1). `SCUT_MAIL_EML_DIR` test mode + `tests/email_channel_spec.sh` (17 checks).
- **`scripts/inbox-watch.sh`** — periodic watcher over every registered project's inbound
  channels (`_inbox.md` + `_inbox/` drops): nudges the lead via `mux_send` only when it is
  idle/done (or stale-busy), leaves fresh-busy/blocked leads alone, optional wake-on-new
  via `INBOX_WATCH_BOOT=1`. Instance contract via `dev-team.env`
  (`TEAM_LEAD`/`MUX_SESSION`/`BOOT_CMD`); host timer example in `scripts/cron/README.md`.
  `tests/inbox_watch_spec.sh` (15 checks).
- Canon: `team-rules/comms.md` §7 — external channels run adapter→router, inbox-first;
  secrets + enabling stay human-only (T4).

### Fixed
- `scut-router.sh --self-test` no longer trips `set -u` in its EXIT-trap cleanup
  (regression check added; gate now at 25 specs).

## [0.6.0] — 2026-07-03

### Added
- **`advisor` archetype** 🦉 — on-demand, read-only consultant for the hard problems
  (`model: fable`, `effort: xhigh`, Mythos-class). Catalog-only: deliberately not wired into
  init/onboard; spawn it consciously when a team needs it.
- **Skill `update-bobs`** — per-project engine update: pull ff-only → `bin/check-compat` →
  re-onboard → "brief the Bobs" inbox note.
- **News box** — installation-wide broadcast: `scripts/news.sh post|read|path`, one file per
  installation (resolved via `$BOBNET_NEWS` → `bobiverse.json:news` → default). Canon in
  `team-rules/news.md`; the standup routine now reads it (`team-rules/routines.md`).
- `docs/KNOWLEDGE.md` — the engine map: layers, dashboard, comms, tools, where-to-find-what.
- `tests/news_spec.sh` (11 checks); the release gate now runs 23 specs.

### Changed
- **Model cut v2** — backend / frontend / dashboard / website / marketing / compliance now
  default to `sonnet`/`xhigh`; `opus`/`xhigh` is reserved for techlead + design.
- `schemas/archetype.schema.json` — `model` enum gains `fable` (additive, existing archetypes
  stay valid; `SCHEMA_VERSION` remains `1`).
- Canon patches: `team-rules/tiers.md` documents the project-level override "staging deploys
  team-autonomous after a full green circle" (T4 stays override-free) · `team-rules/comms.md` §6
  adds the external-co-worker variant (in-house role remains the single delivering instance) ·
  `CONVENTIONS.md` §5 clarifies engine contributions land via inbox, not direct commits.

## [0.5.0] — 2026-07-02

Architecture batch: per-role model+effort resolution, role triggers, image generation backed by
a central secrets store, uid→persona roster (dashboard identity), avatar name override, and
`/api/health`.

## Earlier

Pre-0.5.0 history lives in the git log (`git log --merges main`).
