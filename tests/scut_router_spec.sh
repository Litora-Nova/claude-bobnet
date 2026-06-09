#!/usr/bin/env bash
# tests/scut_router_spec.sh — Behavior-Spec für scripts/scut-router.sh.
#
# SPEC-Quelle: scut-router.sh-Header + PLAN_bobiverse.md §10.
#   Normalisiertes Event (TSV, 6 Felder): channel  external_id  ts_epoch  sender  target  text
#   target:  "@<Agent>"        → gerichtet an Agent im Kontext-Bobiverse
#            "[<uid>]"         → gerichtet an Projekt-Bobiverse (Registry-uid); kein Agent → dessen TEAM_LEAD
#            "[<uid>]@<Agent>" → Projekt + Agent
#            ""                → UNGERICHTET → Review-Queue des Kontext-Bobiverse
#   gerichtet   → schreibt in <ziel>/_inbox.md
#   ungerichtet → schreibt in <kontext>/_review-queue.md
#   Datengetrieben aus projects.registry.json (path/standup/uid) + dev-team.env (TEAM_LEAD).
#   Robust: leere/malformed Zeilen werden übersprungen, kein Crash.
#
# Black-Box: Wegwerf-Registry + zwei Projekt-standup-Ordner in mktemp -d. NIE die echte
# projects.registry.json oder echte standup-Inboxen angefasst.

set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_helper.sh
. "$HERE/_helper.sh"

ROUTER="$SCRIPTS/scut-router.sh"

echo "scut-router.sh — Behavior-Spec"

TMP="$(mktemp -d "${TMPDIR:-/tmp}/scut-router-spec.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/alpha/_dev_team/standup" "$TMP/beta/_dev_team/standup"

cat > "$TMP/registry.json" <<JSON
{ "version":1, "projects":[
  {"uid":"alpha","name":"alpha","label":"Alpha","path":"$TMP/alpha","standup":"$TMP/alpha/_dev_team/standup","theme":"bobiverse","status":"active"},
  {"uid":"beta","name":"beta","label":"Beta","path":"$TMP/beta","standup":"$TMP/beta/_dev_team/standup","theme":"bobiverse","status":"active"}
]}
JSON
printf 'export TEAM_LEAD="Bob"\n' > "$TMP/alpha/_dev_team/dev-team.env"
printf 'export TEAM_LEAD="Zoe"\n' > "$TMP/beta/_dev_team/dev-team.env"

NOW="$(date +%s 2>/dev/null || echo 1700000000)"
ALPHA_INBOX="$TMP/alpha/_dev_team/standup/_inbox.md"
ALPHA_QUEUE="$TMP/alpha/_dev_team/standup/_review-queue.md"
BETA_INBOX="$TMP/beta/_dev_team/standup/_inbox.md"

# route <stdin-events> : füttert den Router mit Kontext=alpha + Demo-Registry.
route() {
  env DEV_TEAM_REGISTRY="$TMP/registry.json" CONTEXT_UID="alpha" bash "$ROUTER"
}
# tab-getrenntes Event bauen (newline-frei).
ev() { printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "$4" "$5" "$6"; }

# ── 1) Gerichtet @Agent im Kontext-Bobiverse → Kontext-Inbox ──────────────────────────────
it "gerichtet @Bill (Kontext alpha) → landet in alpha/_inbox.md mit @Bill"
ev telegram 1 "$NOW" Owner "@Bill" "bitte API-Key rotieren" | route >/dev/null 2>&1
file_has "$ALPHA_INBOX" "@Bill"
file_has "$ALPHA_INBOX" "bitte API-Key rotieren"

it "gerichtet @Bill landet NICHT in der Review-Queue"
[ ! -f "$ALPHA_QUEUE" ] && file_missing "$ALPHA_QUEUE" || not_contains "$(cat "$ALPHA_QUEUE")" "@Bill"

# ── 2) Gerichtet an Projekt [beta] ohne Agent → beta-Inbox an dessen TEAM_LEAD (Zoe) ──────
it "[beta] ohne Agent → beta/_inbox.md an den TEAM_LEAD Zoe (aus beta/dev-team.env)"
ev email 2 "$NOW" extern "[beta]" "Vertrag liegt bei" | route >/dev/null 2>&1
file_has "$BETA_INBOX" "@Zoe"
file_has "$BETA_INBOX" "Vertrag liegt bei"

# ── 3) Gerichtet [beta]@Cid → beta-Inbox an genau diesen Agenten ──────────────────────────
it "[beta]@Cid → beta/_inbox.md an @Cid (Projekt + Agent kombiniert)"
ev github 3 "$NOW" user "[beta]@Cid" "PR review?" | route >/dev/null 2>&1
file_has "$BETA_INBOX" "@Cid"
file_has "$BETA_INBOX" "PR review?"

# ── 4) Ungerichtet (leeres target) → Review-Queue des Kontext-Bobiverse ───────────────────
it "ungerichtet (leeres target) → alpha/_review-queue.md als UNGERICHTET"
ev teams 4 "$NOW" chef "" "wer kann das mal anschauen" | route >/dev/null 2>&1
file_has "$ALPHA_QUEUE" "UNGERICHTET"
file_has "$ALPHA_QUEUE" "wer kann das mal anschauen"

it "ungerichtet landet NICHT in einer Inbox"
not_contains "$(cat "$ALPHA_INBOX")" "wer kann das mal anschauen"

# ── 5) DRYRUN: entscheidet + berichtet, schreibt NICHTS ───────────────────────────────────
it "DRYRUN: gerichtetes Event wird auf stdout als ROUTE inbox gemeldet, ohne Datei-Write"
mkdir -p "$TMP/dry/_dev_team/standup"
cat > "$TMP/registry-dry.json" <<JSON
{ "version":1, "projects":[
  {"uid":"dry","name":"dry","label":"Dry","path":"$TMP/dry","standup":"$TMP/dry/_dev_team/standup","theme":"bobiverse","status":"active"}
]}
JSON
dryout="$(ev telegram 9 "$NOW" Owner "@Cid" "dry-run probe" \
  | env DEV_TEAM_REGISTRY="$TMP/registry-dry.json" CONTEXT_UID="dry" SCUT_ROUTER_DRYRUN=1 bash "$ROUTER" 2>/dev/null)"
contains "$dryout" "ROUTE"
contains "$dryout" "@Cid"
file_missing "$TMP/dry/_dev_team/standup/_inbox.md"

# ── 6) ROBUSTHEIT: malformed / leere Events crashen nicht ─────────────────────────────────
it "leere Zeilen + Zeilen ohne channel werden übersprungen, kein Crash (rc==0)"
ok bash -c 'printf "\n\n\t\t\t\t\t\n" | env DEV_TEAM_REGISTRY="'"$TMP/registry.json"'" CONTEXT_UID="alpha" bash "'"$ROUTER"'"'

it "Event mit zu wenig Feldern (nur channel) crasht nicht (rc==0)"
ok bash -c 'printf "telegram\n" | env DEV_TEAM_REGISTRY="'"$TMP/registry.json"'" CONTEXT_UID="alpha" bash "'"$ROUTER"'"'

it "Event mit unbekanntem [uid] crasht nicht; nutzt das genannte uid als dest (kein Registry-Match → DRYRUN-Report)"
ok bash -c 'printf "telegram\t1\t'"$NOW"'\tx\t[ghost]@Cid\thi\n" | env DEV_TEAM_REGISTRY="'"$TMP/registry.json"'" CONTEXT_UID="alpha" bash "'"$ROUTER"'"'

it "fehlende Registry-Datei → kein Crash (rc==0), nichts in echte Files geschrieben"
ok bash -c 'printf "telegram\t1\t'"$NOW"'\tx\t@Bill\thi\n" | env DEV_TEAM_REGISTRY="'"$TMP/none.json"'" CONTEXT_UID="alpha" bash "'"$ROUTER"'"'

it "Text mit Sonderzeichen (Pipe, Klammern) bleibt erhalten, kein Crash"
ev telegram 7 "$NOW" Owner "@Bill" "deploy? (staging|prod) check" | route >/dev/null 2>&1
file_has "$ALPHA_INBOX" "deploy? (staging|prod) check"

# ── 7) Usage / Self-Test-Modi ─────────────────────────────────────────────────────────────
it "unbekanntes Subcommand → rc!=0 (Usage)"
not_ok bash "$ROUTER" bogus-subcommand

it "mitgelieferter --self-test läuft GRÜN durch (Garfields eingebauter Sanity-Check)"
ok bash "$ROUTER" --self-test

summary
