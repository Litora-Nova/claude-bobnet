#!/usr/bin/env bash
# tests/dashboard_projection_spec.sh — RED spec pinning D-1 (visibility projection
# panel) BEFORE the builder writes the code. Source of the pinned behavior:
#   standup/_design_dashboard-projection.md (D1/D7) and ai-bobnet's
#   docs/CONTRACT-visibility.md schema 1 (frozen interface, §18).
#
# CONTRACT PINNED — dashboard/server/utils/projection.mjs exports:
#
#   async readProjection(standupDir, nowIso)
#     reads "<standupDir>/_projection.json" and returns EITHER
#       { present: false, reason: "missing" | "unreadable" | "unparsable" | "schema" }
#     OR
#       { present: true, projection, ageSeconds, stale }
#     where `projection` is the parsed schema-1 object (verbatim — no field is
#     rewritten, sanitized, or re-escaped: text stays text, contract §4/§18),
#     `ageSeconds` = (nowIso - projection.generated_at) in whole seconds, and
#     `stale` = ageSeconds > NUXT_PROJECTION_STALE_SECONDS (env, default 60).
#   "schema" = parses as JSON but fails schema-1 field/type conformance (unknown
#     TOP-LEVEL fields are tolerated — additive-only versioning, contract §18).
#
# node-testable like beats.mjs/activity.mjs (tests/dashboard_beats_spec.sh style):
# no Nitro/H3 context needed, pure fixtures under mktemp -d (tests/README.md: ALL
# fixtures in mktemp -d, never a committed sample file).
#
# Expected on the unbuilt tree: every check below that touches projection.mjs,
# the route, or the component FAILS (files do not exist yet) — this is the RED
# half of red/green. Report exact counts.
set -uo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/_helper.sh"

MJS="$ENGINE_ROOT/dashboard/server/utils/projection.mjs"
COMPONENT="$ENGINE_ROOT/dashboard/components/ProjectionPanel.vue"
ROUTE="$ENGINE_ROOT/dashboard/server/api/projection.get.ts"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

it "projection.mjs exists (D1)"
ok test -f "$MJS"

# ── Shared fixture factory (generated INTO mktemp, never committed — README §Konventionen) ──
cat > "$WORK/_fixture.mjs" <<'FIXTURE_EOF'
export function baseProjection(overrides = {}) {
  const base = {
    schema: 1,
    generated_at: '2026-09-08T11:34:58+02:00',
    project_uid: 'acme',
    attested_sources: ['stream', 'capacity'],
    stream: { status: 'ok', last_seq: 68, anchor: { value: 68, relationship: 'ok' }, torn_tail: false, undecodable_records: [] },
    capacity: { limit: 12, live: 0, as_of: '2026-09-08T07:58:56+02:00' },
    attention: [],
    agents: {
      'acme-core': { state: 'done', since: '2026-09-08T07:58:57+02:00', message: 'codex-run OK', stale: false, attested: false, attempt: null },
    },
    anomalies: { unregistered_logs: 0, unparsable_lines: 0, uid_mismatches: 0, undecodable_records: 0 },
  }
  return { ...base, ...overrides }
}
FIXTURE_EOF

genjson() {  # genjson <overrides-js-object-literal> -> prints JSON on stdout
  node --input-type=module -e "
import { baseProjection } from 'file://$WORK/_fixture.mjs';
console.log(JSON.stringify(baseProjection($1)));
"
}

write_fixture() {  # write_fixture <dir> <json-text>
  mkdir -p "$1"
  printf '%s' "$2" > "$1/_projection.json"
}

rp() {  # rp <standupDir> <nowIso> <js-expr on `r`> — evaluate readProjection(...)
  node --input-type=module -e "
import { readProjection } from 'file://$MJS';
const r = await readProjection('$1', '$2');
console.log($3);
" 2>/dev/null
}

# ── 1. Sample → parsed fields, incl. ageSeconds ──────────────────────────────
D_SAMPLE="$WORK/sample"
write_fixture "$D_SAMPLE" "$(genjson "{}")"

it "1a. sample: present:true"
eq "$(rp "$D_SAMPLE" "2026-09-08T11:34:58+02:00" "r.present")" "true"

it "1b. sample: project_uid passed through verbatim"
eq "$(rp "$D_SAMPLE" "2026-09-08T11:34:58+02:00" "r.projection.project_uid")" "acme"

it "1c. sample: stream.status passed through"
eq "$(rp "$D_SAMPLE" "2026-09-08T11:34:58+02:00" "r.projection.stream.status")" "ok"

it "1d. sample: agents object keeps registry-uid keys"
eq "$(rp "$D_SAMPLE" "2026-09-08T11:34:58+02:00" "Object.keys(r.projection.agents).join(',')")" "acme-core"

it "1e. sample: ageSeconds is a number on the present:true shape"
eq "$(rp "$D_SAMPLE" "2026-09-08T11:34:58+02:00" "typeof r.ageSeconds")" "number"

it "1f. sample: ageSeconds reflects the now/generated_at offset (5s later)"
eq "$(rp "$D_SAMPLE" "2026-09-08T11:35:03+02:00" "r.ageSeconds")" "5"

# ── 2. Missing file → present:false, reason:"missing" ────────────────────────
D_MISSING="$WORK/missing"; mkdir -p "$D_MISSING"

it "2. missing _projection.json -> {present:false, reason:'missing'} (unknown, not empty — contract §4)"
eq "$(rp "$D_MISSING" "2026-09-08T11:34:58+02:00" "r.present + '|' + r.reason")" "false|missing"

# ── 3. Garbage (unparsable JSON) → reason:"unparsable" ────────────────────────
D_GARBAGE="$WORK/garbage"; mkdir -p "$D_GARBAGE"
printf '{ not valid json ]]]' > "$D_GARBAGE/_projection.json"

it "3. unparsable JSON -> {present:false, reason:'unparsable'}"
eq "$(rp "$D_GARBAGE" "2026-09-08T11:34:58+02:00" "r.present + '|' + r.reason")" "false|unparsable"

# ── 4. Wrong type on a known field → reason:"schema" ─────────────────────────
D_SCHEMA="$WORK/schema-wrong-type"
write_fixture "$D_SCHEMA" "$(genjson "{agents: []}")"   # agents MUST be an object (schema-1 §18)

it "4. agents as an array (wrong type) -> {present:false, reason:'schema'}"
eq "$(rp "$D_SCHEMA" "2026-09-08T11:34:58+02:00" "r.present + '|' + r.reason")" "false|schema"

# ── 5. Unknown TOP-LEVEL field is tolerated (contract §18: additive-only) ────
D_UNKNOWN="$WORK/unknown-field"
write_fixture "$D_UNKNOWN" "$(genjson "{future_pillar_field: 'not in schema 1 yet'}")"

it "5. unknown additive top-level field is tolerated -> still present:true"
eq "$(rp "$D_UNKNOWN" "2026-09-08T11:34:58+02:00" "r.present")" "true"

# ── 6. Hostile text survives verbatim as data (never re-interpreted/escaped) ─
cat > "$WORK/hostile.txt" <<'HOSTILE_EOF'
<script>alert(1)</script> "double" 'single' back\slash
line-two-after-a-real-newline
HOSTILE_EOF

cat > "$WORK/hostile_check.mjs" <<'CHECK_EOF'
import fs from 'node:fs/promises'
const [, , mjsPath, hostileFile, dir] = process.argv
const { readProjection } = await import('file://' + mjsPath)
const msg = await fs.readFile(hostileFile, 'utf8')
const proj = {
  schema: 1, generated_at: '2026-09-08T11:34:58+02:00', project_uid: 'acme',
  attested_sources: ['stream'],
  stream: { status: 'ok', last_seq: 1, anchor: { value: 1, relationship: 'ok' }, torn_tail: false, undecodable_records: [] },
  capacity: { limit: 12, live: 0, as_of: '2026-09-08T07:58:56+02:00' },
  attention: [{ kind: 'other', agent: 'acme-core', reason: msg, since: '2026-09-08T07:58:57+02:00', attested: false }],
  agents: { 'acme-core': { state: 'blocked', since: '2026-09-08T07:58:57+02:00', message: msg, stale: false, attested: false, attempt: null } },
  anomalies: { unregistered_logs: 0, unparsable_lines: 0, uid_mismatches: 0, undecodable_records: 0 },
}
await fs.mkdir(dir, { recursive: true })
await fs.writeFile(dir + '/_projection.json', JSON.stringify(proj))
const r = await readProjection(dir, '2026-09-08T11:34:58+02:00')
const okMsg = !!r.present && r.projection.agents['acme-core'].message === msg
const okReason = !!r.present && r.projection.attention[0].reason === msg
console.log(okMsg && okReason ? 'PASS' : 'FAIL')
CHECK_EOF

it "6. hostile text (<script>, quotes, backslash, real newline) survives verbatim as data"
eq "$(node "$WORK/hostile_check.mjs" "$MJS" "$WORK/hostile.txt" "$WORK/hostile" 2>/dev/null)" "PASS"

# ── 7. Staleness boundary — exactly at, and one over, NUXT_PROJECTION_STALE_SECONDS ──
# Default threshold is 60s (design D1); generated_at picked on a clean minute so the
# math is exact. Rule pinned: ageSeconds > threshold, i.e. == threshold is NOT stale.
D_STALE="$WORK/stale"
write_fixture "$D_STALE" "$(genjson "{generated_at: '2026-09-08T12:00:00+02:00'}")"

it "7a. ageSeconds exactly 60 (== default NUXT_PROJECTION_STALE_SECONDS) -> NOT stale"
eq "$(rp "$D_STALE" "2026-09-08T12:01:00+02:00" "r.ageSeconds + '|' + r.stale")" "60|false"

it "7b. ageSeconds 61 (one over default threshold) -> stale"
eq "$(rp "$D_STALE" "2026-09-08T12:01:01+02:00" "r.ageSeconds + '|' + r.stale")" "61|true"

# ── 8. Age is TZ-independent (offset-bearing ISO in, process TZ must not matter) ──
AGE_UTC="$(TZ=UTC node --input-type=module -e "
import { readProjection } from 'file://$MJS';
const r = await readProjection('$D_STALE', '2026-09-08T12:01:01+02:00');
console.log(r.ageSeconds);
" 2>/dev/null)"
AGE_BERLIN="$(TZ=Europe/Berlin node --input-type=module -e "
import { readProjection } from 'file://$MJS';
const r = await readProjection('$D_STALE', '2026-09-08T12:01:01+02:00');
console.log(r.ageSeconds);
" 2>/dev/null)"

it "8. ageSeconds identical under TZ=UTC and TZ=Europe/Berlin (offset-bearing ISO, contract §9)"
eq "$AGE_UTC" "$AGE_BERLIN"

# ── 9. Grep pins — component/route existence + hard style rules ─────────────
it "9a. server/api/projection.get.ts exists (D2)"
ok test -f "$ROUTE"

it "9b. no v-html anywhere in ProjectionPanel.vue (untrusted agent text, contract §18/§4)"
not_ok grep -q "v-html" "$COMPONENT"

it "9c. no emoji codepoint in ProjectionPanel.vue (dashboard hard rule, dashboard/CLAUDE.md NO-EMOJI)"
not_ok grep -P "[\x{1F300}-\x{1FAFF}\x{2600}-\x{27BF}\x{2190}-\x{21FF}\x{2B00}-\x{2BFF}]" "$COMPONENT"

it "9d. no emoji codepoint in projection.get.ts"
not_ok grep -P "[\x{1F300}-\x{1FAFF}\x{2600}-\x{27BF}\x{2190}-\x{21FF}\x{2B00}-\x{2BFF}]" "$ROUTE"

it "9e. no emoji codepoint in projection.mjs"
not_ok grep -P "[\x{1F300}-\x{1FAFF}\x{2600}-\x{27BF}\x{2190}-\x{21FF}\x{2B00}-\x{2BFF}]" "$MJS"

summary
