#!/usr/bin/env bash
# tests/pre_push_floor_spec.sh — hooks/pre-push-identity-floor.sh (Issue #59).
#
# Black-box against the REAL git pre-push mechanism: EVERY scenario gets its OWN throwaway
# bare "remote" + work repo (via fresh_repo) with the hook installed at .git/hooks/pre-push,
# exercised via actual `git push`. Deliberately NOT one shared branch across scenarios — an
# earlier iteration of this spec shared a single branch/file across cases and content from one
# scenario (e.g. a leaked AWS key) kept bleeding into later commits via accumulated file state,
# which made failures hard to attribute. Full isolation costs a bit of repetition, buys
# correctness.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_helper.sh
. "$HERE/_helper.sh"

HOOK="$ENGINE_ROOT/hooks/pre-push-identity-floor.sh"

echo "pre-push-identity-floor.sh — Behavior-Spec"

it "bash -n sauber"
ok bash -n "$HOOK"

ROOT="$(mktemp -d "${TMPDIR:-/tmp}/pre-push-floor-spec.XXXXXX")"
trap 'rm -rf "$ROOT"' EXIT
N=0

# fresh_repo -> sets $WORK to a brand-new work-repo path (bare remote + hook installed),
# already has ONE commit on main with canon identity + matching team email (a believable
# starting point — most scenarios add ONE more commit on top and push that).
fresh_repo() {
  N=$((N+1))
  WORK="$ROOT/r$N/work"
  mkdir -p "$ROOT/r$N"
  git init -q --bare "$ROOT/r$N/remote.git"
  git init -q -b main "$WORK"
  git -C "$WORK" remote add origin "$ROOT/r$N/remote.git"
  mkdir -p "$WORK/.git/hooks"
  cp "$HOOK" "$WORK/.git/hooks/pre-push"
  chmod +x "$WORK/.git/hooks/pre-push"
  commit_as "Garfield (Acme Architect)" "team@example.com" "initial canon commit" "base"
  ( cd "$WORK" && env DEV_TEAM_EMAIL=team@example.com git push -q origin main:main )
}

# commit_as <name> <email> <msg> [content] — appends content to file.txt (fresh name per call
# so nothing accumulates across commits within a scenario either), commits with --allow-empty
# (a pure identity test case needs no file content to still count as a real commit). Avoids the
# GIT_AUTHOR_*/COMMITTER_*-env-outranks--c-user.name= trap (git's identity resolution checks env
# before config) by unsetting those vars for the git invocation itself.
commit_as() {
  local name="$1" email="$2" msg="$3" content="${4:-}"
  if [ -n "$content" ]; then printf '%s\n' "$content" > "$WORK/file-$RANDOM.txt"; fi
  ( cd "$WORK"
    env -u GIT_AUTHOR_NAME -u GIT_AUTHOR_EMAIL -u GIT_COMMITTER_NAME -u GIT_COMMITTER_EMAIL \
      git -c user.name="$name" -c user.email="$email" add -A
    env -u GIT_AUTHOR_NAME -u GIT_AUTHOR_EMAIL -u GIT_COMMITTER_NAME -u GIT_COMMITTER_EMAIL \
      git -c user.name="$name" -c user.email="$email" commit -q --allow-empty -m "$msg" )
}

push() { ( cd "$WORK" && env "$@" git push origin main:main ) 2>&1; }

# ── (1) Kanon-Identität, DEV_TEAM_EMAIL passt → Push erlaubt ───────────────────────────────
fresh_repo
commit_as "Garfield (Acme Architect)" "team@example.com" "second canon commit"
push DEV_TEAM_EMAIL=team@example.com >/dev/null 2>&1; rc=$?
it "(1) Kanon-Identität + passende Team-Mail → Push erlaubt"
eq "$rc" "0"

# ── (2) Falsche FORM (kein Klammer-Display) → Push blockiert ───────────────────────────────
fresh_repo
commit_as "Some Human" "personal@gmail.com" "bad shape"
out="$(push DEV_TEAM_EMAIL=team@example.com)"; rc=$?
it "(2) Identität ohne Klammer-Display → Push blockiert (rc!=0)"
neq "$rc" "0"
it "(2) ... Grund im Stderr genannt (Kanon-Form)"
contains "$out" "doesn't match the canon shape"
it "(2) ... FLOOR-TRIPPED-Zeile mit Bypass-Hinweis"
contains "$out" "BOBNET_PUSH_FLOOR_SKIP=1"

# ── (3) Kanon-FORM korrekt, aber falsche Team-Mail-Domain → Push blockiert ─────────────────
fresh_repo
commit_as "Garfield (Acme Architect)" "garfield.personal@gmail.com" "right shape wrong domain"
out="$(push DEV_TEAM_EMAIL=team@example.com)"; rc=$?
it "(3) Kanon-Form korrekt, Mail-Domain falsch → trotzdem blockiert"
neq "$rc" "0"
it "(3) ... Grund nennt die abweichende Mail"
contains "$out" "does not match the configured team email"

# ── (4) Ohne DEV_TEAM_EMAIL konfiguriert: nur die FORM zählt, jede Mail geht durch ──────────
fresh_repo
commit_as "Garfield (Acme Architect)" "anything@whatever.example" "shape only, no email pin"
out="$(push)"; rc=$?
it "(4) Kein DEV_TEAM_EMAIL konfiguriert: Kanon-Form allein reicht → Push erlaubt"
eq "$rc" "0"

# ── (5) Secret-Muster im Diff → Push blockiert trotz sauberer Identität ────────────────────
fresh_repo
commit_as "Garfield (Acme Architect)" "team@example.com" "leaked aws key" "AKIAABCDEFGHIJKLMNOP"
out="$(push DEV_TEAM_EMAIL=team@example.com)"; rc=$?
it "(5) AWS-Key-Muster im Diff → blockiert trotz sauberer Identität"
neq "$rc" "0"
it "(5) ... Grund nennt secret/token pattern"
contains "$out" "secret/token pattern"

# ── (5b) GitLab-PAT-Muster (glpat-) im Diff → ebenfalls blockiert ─────────────────────────
fresh_repo
commit_as "Garfield (Acme Architect)" "team@example.com" "leaked gitlab pat" "glpat-ABCDEFGHIJKLMNOPQRST"
out="$(push DEV_TEAM_EMAIL=team@example.com)"; rc=$?
it "(5b) GitLab-PAT-Muster (glpat-) im Diff → blockiert trotz sauberer Identität"
neq "$rc" "0"
it "(5b) ... Grund nennt secret/token pattern"
contains "$out" "secret/token pattern"

# ── (6) fremde Email-Adresse im COMMITTETEN INHALT (nicht nur Metadaten) → blockiert ───────
fresh_repo
commit_as "Garfield (Acme Architect)" "team@example.com" "leaked private address in content" \
  "Kontakt bei Rückfragen: privat.mensch@gmail.com"
out="$(push DEV_TEAM_EMAIL=team@example.com)"; rc=$?
it "(6) fremde Email-Adresse im Inhalt (nicht nur Metadaten) → blockiert"
neq "$rc" "0"
it "(6) ... Grund nennt 'added content contains email'"
contains "$out" "added content contains email"

# ── (7) Bypass-Flag: BOBNET_PUSH_FLOOR_SKIP=1 lässt einen sonst blockierten Push durch ─────
fresh_repo
commit_as "Some Human" "personal@gmail.com" "bad shape, but bypassed"
out="$(push DEV_TEAM_EMAIL=team@example.com BOBNET_PUSH_FLOOR_SKIP=1)"; rc=$?
it "(7) Bypass-Flag lässt einen sonst blockierten Push durch"
eq "$rc" "0"
it "(7) ... Skip wird trotzdem laut geloggt (kein stiller Bypass)"
contains "$out" "SKIPPED"

# ── (8) Mehrere Commits in einem Push: JEDER wird geprüft, nicht nur die Spitze ────────────
fresh_repo
commit_as "Garfield (Acme Architect)" "team@example.com" "commit A ok"
commit_as "Garfield (Acme Architect)" "team@example.com" "commit B ok"
commit_as "Bad Middle Commit" "bad@gmail.com" "commit C bad, buried in the middle"
commit_as "Garfield (Acme Architect)" "team@example.com" "commit D ok, on top of the bad one"
out="$(push DEV_TEAM_EMAIL=team@example.com)"; rc=$?
it "(8) ein einzelner schlecht-identifizierter Commit MITTEN in mehreren guten → trotzdem blockiert"
neq "$rc" "0"
it "(8) ... genau der schlechte Commit wird benannt, nicht nur irgendeiner"
contains "$out" "bad@gmail.com"

# ── (9) neuer Branch (remote-sha = 40 Nullen): wird ebenfalls geprüft, nicht übersprungen ──
fresh_repo
git -C "$WORK" checkout -q -b feature/bad-new-branch main
commit_as "Someone Else" "someone@gmail.com" "bad identity on a brand-new branch"
out="$( cd "$WORK" && git push origin feature/bad-new-branch:feature/bad-new-branch 2>&1)"; rc=$?
it "(9) neuer Branch mit schlechter Identität → ebenfalls blockiert (nicht als Sonderfall übersprungen)"
neq "$rc" "0"

# ── (10) Branch-Löschung (local-sha = 40 Nullen): No-Op, kein Crash ────────────────────────
fresh_repo
git -C "$WORK" checkout -q -b feature/to-delete main
commit_as "Garfield (Acme Architect)" "team@example.com" "good commit for the delete-test branch"
est_out="$( cd "$WORK" && env DEV_TEAM_EMAIL=team@example.com git push origin feature/to-delete:feature/to-delete 2>&1)"; est_rc=$?
it "(10) Setup: sauberer Etablierungs-Push für den Löschungstest gelingt"
eq "$est_rc" "0"
git -C "$WORK" checkout -q main
out="$( cd "$WORK" && git push origin :feature/to-delete 2>&1)"; rc=$?
it "(10) Branch-Löschung wird nicht geprüft (No-Op, kein Crash)"
eq "$rc" "0"

# ── (11) Self-Test-Modus läuft durch (Sanity, zählt NICHT als Gate — tests.md-Konvention) ──
it "(11) --self-test läuft grün durch (eigener Modus, kein Gate-Ersatz)"
ok bash "$HOOK" --self-test

summary
