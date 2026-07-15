# Changelog

All notable engine changes are documented here. Versioning follows SemVer (`VERSION`,
human-facing); machine compatibility is anchored separately by `SCHEMA_VERSION` (integer) —
see `.claude/rules/contract.md`. `skills/update-bobs` points teams here after an update.

## [0.15.0] — 2026-07-15

### Added
- **`bin/recycle <uid>`** — orderly lead-session swap in ONE command (PO order
  2026-07-15): a long-running lead whose context has filled up is handed over
  (continuity note requested via nudge, receipt verified through the lead's
  heartbeat-log line-count — the same delivered-means-heartbeat principle the
  0.14.0 watcher uses, never the mux return code), then killed **measured on the
  outcome**, rebooted via `mux_boot` with an inbox-first standup briefing written
  BEFORE the spawn (headless-safe), and verified through a fresh lead heartbeat.
  Guards: never kill without a configured `BOOT_CMD`; a fresh-`busy`/`blocked`
  lead is only recycled with `--force`; a handover timeout **aborts** instead of
  silently going hard (`--hard` is an explicit caller decision); `--yes` for
  automation (Colonel/cron), `--dry-run` touches nothing. Documented limit:
  graceful handover is only realistic with an attached client (zellij delivers
  drafts headless) — automation is expected to run `--hard` after a continuity
  freshness check. New `tests/recycle_spec.sh` (33 checks), suite now 28 specs.
- `scripts/dev-team.env.example` now documents the `MUX_SESSION` / `BOOT_CMD` /
  `INBOX_WATCH_ALERT_CMD` instance contract in one place.

### Fixed
- **inbox-watch boot path runs `BOOT_CMD` with the project env sourced** — the
  command used to start in a fresh shell where `$PROJECT_ROOT` (and everything
  else from `dev-team.env`) was empty; now the project's `dev-team.env` is
  sourced in front of the boot command (same cure `bin/recycle` ships). The spec
  covers the real boot path for the first time (live `mux_boot` run, marker file
  asserts the expanded env; skipped cleanly where tmux is unavailable).

## [0.14.0] — 2026-07-09

### Fixed
- **inbox-watch: delivery is now verified via the lead's heartbeat, not the mux return
  code** (#48; field incident: customer mail sat unseen for a day). Previously a nudge —
  or even a report-only pass with no wake path at all — finalized the watch state
  immediately, silently swallowing the entry. Two real-world failure modes drove this:
  report-only projects (no `MUX_SESSION`) were marked handled although nobody was woken,
  and zellij delivers `write-chars` to sessions without an attached client as an
  **unsubmitted draft** while the send returns success. The watcher now keeps a
  `PENDING` state per event (signature + lead-log line-count snapshot + attempt counter):
  delivered means the lead's heartbeat log grew since the nudge (line count, not
  timestamps — the log has minute resolution); unverified events are re-nudged up to
  `INBOX_WATCH_MAX_NUDGE` times (default 3). On re-nudge attempts a bare Enter is sent
  first (new `mux_flush_draft` in `lib/mux.sh`, zellij only — submits a possibly stuck
  draft once a client attaches; tmux path unchanged). Old plain-signature state files
  are still read (treated as final).

### Added
- **Escalation hook `INBOX_WATCH_ALERT_CMD`** (opt-in, per-project `dev-team.env` or
  unit env as fleet fallback): runs exactly once per event — `$ALERT_CMD <uid> <lead>
  <standup-path>` — when re-nudge attempts are exhausted unverified, or when new entries
  arrive with no wake path at all (report-only). Wire it to the instance's messenger
  script to page a human. Without an alert command the watcher still finalizes (no
  endless loop) but logs the case loudly as swallowed and counts it in the summary line.
- **Gate-note hardening batch** (from this release's full gate): the watcher now serializes
  itself via `flock` (state-dir lock; overlapping timer/cron runs can no longer double-fire
  the once-per-event escalation), a failing alert command is counted separately in the
  summary (no longer masked as escalated), a corrupt `PENDING` state line (empty signature,
  non-numeric fields) conservatively starts a fresh cycle instead of permissively verifying,
  and the heartbeat-verification heuristic's known limit (a lead heartbeating for unrelated
  work counts as woken) is documented in the header and `team-rules/comms.md`.

### Added
- **Known-sender mapping for the email channel** (#53): customer mail is the *main* case for
  a project mailbox, but without `[uid]@Agent` addressing it used to land undirected in the
  review queue. `scripts/channels/email.sh` now matches the `From:` address (case-insensitive)
  against a per-project map file as a third, lowest-priority fallback (subject tag > plus
  address > known sender): `SCUT_MAIL_SENDERS_FILE`, default
  `$PROJECT_ROOT/_dev_team/team-rules/scut-mail.senders` — one address per line, optional
  explicit `@Agent` target (default `TEAM_LEAD`, overridable via
  `SCUT_MAIL_SENDERS_DEFAULT_AGENT`), `#` comments and blank lines ignored. A match delivers
  the message **directed** into the project inbox (canon line unchanged, `via Mail von …`
  preserved); unknown senders keep the review-queue behavior byte-for-byte. The map file is
  **instance data** — never committed to this engine repo. Docs: `team-rules/comms.md` §7,
  `scripts/channels/README.md`.

### Fixed
- **Follow-up batch from the 0.12.0 gate notes** (#52):
  - `bridge-receive.sh`: the ACCEPT audit line is now written **after** the successful inbox
    append; the fail-closed guard before delivery is a pure writability preflight (no entry).
    Previously an append failure left a contradictory `ACCEPT` followed by
    `REJECT: append failed` for the same message in the log. A post-append audit-write
    failure warns on stderr but no longer misreports (the delivery already happened);
    covered by a negative spec assertion.
  - `bobnet-send.sh`: the receiver's exit 3 (infra/audit failure, fail-closed since 0.12.0)
    is now passed through as the sender's own exit 3 instead of being folded into exit 2
    (REJECT) — the two classes have different retry semantics (infra: retry later may help;
    reject: do not retry blindly). Distinct messages on stderr, raw rc still in
    `BOBNET_SEND_LOG`.
  - `email.sh`: the size-estimate behavior for exotic/misdeclared `Content-Transfer-Encoding`
    (raw length treated as the upper bound for everything non-base64) is now pinned by spec —
    no code change needed, no expansion bug found.
  - `tests/bridge_spec.sh`: fixture peer renamed to the generic `peerB` (white-label hygiene;
    same rename applied to the `peers.json` example in the `bobnet-send.sh` header).

## [0.12.0] — 2026-07-05

### Fixed
- **BobNet-Bridge hardening, medium/low batch** (#51, from the cross-model review,
  range a997383..fd1457a):
  - `bridge-receive.sh`: the mandatory ACCEPT audit is now **fail-closed** — if the audit
    write fails, the message is not delivered (new exit code 3, documented in the header)
    instead of landing in the inbox without an audit trail. REJECT audit failures still
    never block a rejection (best-effort there).
  - `bridge-receive.sh`: the 4KB limit now counts **bytes**, not shell characters —
    `${#raw}` undercounts in a multibyte locale, which could let an oversized message slip
    past the check and skew the audit's byte count.
  - `bridge-receive.sh`: the peer argument is now validated against a strict
    `^[A-Za-z0-9_-]{1,32}$` pattern, and second-hand display names (`peers.json` `lead`,
    the `TEAM_LEAD` fallback from `dev-team.env`) are control-character/newline-stripped
    and length-capped (64) — closes a log-/inbox-line spoofing path.
  - `bobnet-send.sh`: `BRIDGE_TRANSPORT_CMD` now only takes effect with the new
    `BRIDGE_TEST_MODE=1` — without it, the override is ignored (warning, normal ssh/
    forced/recv path runs instead), closing a shell-injection path through an untrusted
    `peers.json`.
  - `bobnet-send.sh`: adds a best-effort sender audit (`BOBNET_SEND_LOG`, append-only,
    ts·peer·bytes·rc per send), symmetric to the receiver's `BRIDGE_LOG` — `team-rules/
    comms.md` already called for bidirectional audit.
  - `scripts/channels/email.sh`: the persisted attachment/body pipeline now bounds its I/O
    instead of decoding unboundedly before checking size — new `SCUT_MAIL_BODY_MAX`
    (default 256 KB, UTF-8-safe truncation of the persisted full text, which previously
    had no cap at all), `SCUT_MAIL_ATTACH_MAX_COUNT` (default 10 per mail) and
    `SCUT_MAIL_ATTACH_MAX_TOTAL` (default 50 MB aggregate per mail); oversized attachments
    are now estimated from their encoded (base64) length and skipped **before** the full
    decode. Same degrade-per-mail semantics as before (digest note, files stay in the
    mailbox, `SCUT_MAIL_ATTACH_STRICT` still respected).
  - `scripts/channels/email.sh`: the "persistence failed" note no longer misreports
    "0 Anhänge" when only the body write failed (no attachments involved).
  - `tests/email_channel_spec.sh`: the unwritable-attachment-dir fixture now uses an
    ENOTDIR path instead of `chmod 555`, so it fails deterministically even when the
    suite runs as root; adds a direct offset-file assertion (via the new, test-only
    `SCUT_MAIL_EML_OFFSET_TEST`) for the STRICT-vs-default no-loss invariant from 0.11.0,
    not just its stderr message. `tests/bridge_spec.sh` now at 67 checks,
    `tests/email_channel_spec.sh` at 55.

## [0.11.0] — 2026-07-05

### Added
- **Email persistence-failure semantics are now operator-selectable** (`email.sh`, #50, from
  the cross-model review). Default stays best-effort (deliver, advance the offset, note the
  failure in the line) with a documented recovery path (rewind the anchor to the last good
  UID). `SCUT_MAIL_ATTACH_STRICT=1` instead keeps the offset put and stops the poll on a
  persistence failure, so the UID is re-delivered on the next poll (no attachment loss, at
  the cost of a head-of-line stall on a permanent failure — loud on stderr, never a silent
  loss). `tests/email_channel_spec.sh` at 39 checks.

## [0.10.0] — 2026-07-05

### Fixed
- **Bridge sender no longer puts the message in the SSH command position** (`bobnet-send.sh`,
  #49, from a cross-model review): the payload now always goes over **stdin**, never as the
  ssh remote command, so it can never be executed as shell input on a mis-/unwired receiver.
  Peers must declare a safe receive mode in `peers.json` — `"forced": true` (forced-command
  key that reads stdin) or `"recv": "<remote-cmd>"` (explicit trusted receive command);
  neither → the sender refuses (fail hard). `tests/bridge_spec.sh` now at 45 checks (ssh
  shim captures stdin separately from argv).

## [0.9.0] — 2026-07-05

### Added
- **Email attachments are persisted** (`scripts/channels/email.sh`, #46 — field-proven
  "digest + full text" pattern): with `SCUT_MAIL_ATTACH_DIR` set, every mail writes its full
  text as `<prefix>-body.txt` (with From/Date/Subject header) and each attachment as
  `<prefix>-<name>` into the media dir. Filenames are ASCII-sanitized (RFC-2231 decoded,
  NFKD, traversal-safe — regression-asserted), same-name attachments of one mail get a
  dedup suffix, oversized ones are skipped and noted (`SCUT_MAIL_ATTACH_MAX`, default
  10 MB). Persistence errors degrade per mail (noted in the line, files stay in the
  mailbox) — a write failure never stalls the poll batch. Unset = previous count-only
  behavior. `tests/email_channel_spec.sh` now at 35 checks.

### Fixed
- `inbox-watch` also watches the **review queue** (`_review-queue.md`) — undirected
  router mail (e.g. customer mail without a `[uid]` tag) no longer sits unnoticed; the
  state-format change causes one harmless re-announce round on rollout.
- EML test mode no longer leaks a false non-zero exit from the last poll iteration.

## [0.8.0] — 2026-07-04

### Added
- **BobNet bridge** (`scripts/bridge-receive.sh` + `scripts/bobnet-send.sh`) — connect two
  bobiverse installations inbox-first and agent-agnostic. The receiver runs as the **forced
  command** of a dedicated, direction-scoped SSH key (`restrict` + `from=` pinned): peer
  identity comes from the authorized_keys line (never from the client), the message arrives
  as pure data (`SSH_ORIGINAL_COMMAND`, max 4 KB, exactly one line, control chars stripped),
  addressing is mandatory (`[<uid>]` / `[<uid>]@<Agent>`), the receiver resolves the target
  inbox from the registry itself (no client paths), stamps timestamp + peer server-side,
  appends with `flock`, and audit-logs every accept/reject. The sender resolves peers from a
  `peers.json` and propagates remote rejects (no blind retries). Canon: `team-rules/comms.md`
  §7.4; key creation/authorization stays human-only (T4). `tests/bridge_spec.sh` (38 checks,
  incl. an ssh-argv shim and a send→receive roundtrip without SSH).
- `tests/exec_mode_spec.sh` — repo-wide guard that every script is executable in the git
  index (a script had shipped as 100644; 12 legacy files fixed along the way).

### Fixed
- `news.sh read` rejects a non-numeric count cleanly (usage + exit 2) instead of a cryptic
  `tail` error.

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
