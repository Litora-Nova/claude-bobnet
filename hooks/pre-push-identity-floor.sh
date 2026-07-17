#!/usr/bin/env bash
# hooks/pre-push-identity-floor.sh — git pre-push hook: identity + secret/PII floor (Issue #59).
#
# Why: two field incidents drove this. (1) A private email address ended up as commit author
# in a PUBLIC repo — stale `.git/config` fallback in a session that skipped the identity
# wrapper. The compliance gate caught it, but only AFTER a push to a feature branch already
# happened. (2) Generally: nothing stopped a push before it left the machine. This hook is a
# CLIENT-SIDE FLOOR that runs before `git push` leaves — it is NOT the compliance gate (that
# stays the judgment call, runs server/review-side, and sees more than a client hook can). This
# is a cheap, fast, opt-in early warning that catches the common accidental case.
#
# Checks (per commit newly pushed on each ref):
#   (a) author AND committer identity match the canon shape from team-rules/commits.md:
#       "<Name> (<Display> [<Role>]) <Email>" — a bare "Your Name <you@example.com>" or any
#       git-config fallback that never went through scripts/git-identity.sh fails this.
#   (b) if DEV_TEAM_EMAIL is resolvable (dev-team.env, sourced the same way as other engine
#       scripts), author/committer email AND any email address appearing in the pushed diff
#       must match it — catches a private address leaking either as commit metadata or as
#       committed CONTENT (the actual field incident).
#   (c) the diff carries none of a short, well-known set of secret/token patterns (AWS access
#       key, PEM private key header, GitHub/GitLab/Slack/Anthropic token prefixes). This is NOT
#       a general secret scanner — it is a floor for the common, cheaply-detectable cases. This
#       list is minimal BY DESIGN (Riker/#59 review) — the Anthropic prefix was the last accepted
#       addition, not a precedent for open-ended growth.
#
# Bypass (documented, not hidden): BOBNET_PUSH_FLOOR_SKIP=1 git push — skips ALL checks, still
# logs loudly to stderr that it was skipped. The floor is opt-in infrastructure, not a
# replacement for judgment; a legitimate reason to bypass (e.g. a deliberate cross-org
# Co-Authored-By trailer that isn't the pushing identity) always exists somewhere.
#
# Wiring: NOT auto-installed by cloning this repo (`.git/hooks/` is never version-controlled).
# `bin/onboard` writes an idempotent wrapper into `.git/hooks/pre-push` that execs this script —
# same pattern as the `.claude/hooks/*` wrappers, just targeting git's hook slot instead. Opt-in:
# onboard skips the write if a pre-push hook already exists there and isn't our own wrapper
# (never clobbers a human's custom hook).
#
# Self-test: `hooks/pre-push-identity-floor.sh --self-test` builds a throwaway repo + fake
# remote and exercises the real git pre-push protocol end-to-end. Per team-rules/tags/tests.md
# convention this is a sanity check, NOT the gate — the gate is tests/pre_push_floor_spec.sh.
#
# Git pre-push hook contract: invoked as `<hook> <remote-name> <remote-url>`, reads stdin lines
# "<local-ref> <local-sha1> <remote-ref> <remote-sha1>" (one per ref being pushed). Non-zero
# exit aborts the ENTIRE push (all refs), per git's own hook semantics — not something this
# script controls.
set -uo pipefail

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENGINE_ROOT="$(cd "$HOOK_DIR/.." && pwd)"
ZERO_SHA="0000000000000000000000000000000000000000"

# --- optionales dev-team.env sourcen, gleiche Kaskade wie hooks/deploy-guard.sh ---
for env_candidate in \
  "${DEV_TEAM_ENV:-}" \
  "$ENGINE_ROOT/scripts/dev-team.env" \
  "$ENGINE_ROOT/../../_dev_team/dev-team.env"; do
  [ -n "$env_candidate" ] && [ -f "$env_candidate" ] && { . "$env_candidate"; break; }
done
EXPECTED_EMAIL="${DEV_TEAM_EMAIL:-}"

# Canon-Shape aus team-rules/commits.md: "<Name> (<Display> [<Role>]) <Email>" — Klammerinhalt
# beliebig (Display allein oder Display+Role), spitze Klammern um eine plausible Email.
IDENTITY_RE='^[^(<]+ \([^()]+\) <[^<>@]+@[^<>]+>$'

# secret/token-Muster: bewusst KURZE, gut belegte Liste (kein General-Purpose-Scanner).
SECRET_PATTERNS=(
  'AKIA[0-9A-Z]{16}'
  '\-\-\-\-\-BEGIN [A-Z ]*PRIVATE KEY\-\-\-\-\-'
  'ghp_[A-Za-z0-9]{36}'
  'github_pat_[A-Za-z0-9_]{20,}'
  'glpat-[A-Za-z0-9_-]{20,}'
  'xox[baprs]-[A-Za-z0-9-]+'
  'sk-ant-[A-Za-z0-9_-]{20,}'
)

warn() { printf 'pre-push-identity-floor: %s\n' "$*" >&2; }

check_identity() {
  local commit="$1" role="$2" ident="$3"
  if ! printf '%s' "$ident" | grep -qE "$IDENTITY_RE"; then
    warn "commit ${commit:0:12}: $role identity doesn't match the canon shape '<Name> (<Display> [<Role>]) <Email>': $ident"
    return 1
  fi
  if [ -n "$EXPECTED_EMAIL" ]; then
    local email; email="$(printf '%s' "$ident" | sed -n 's/.*<\(.*\)>.*/\1/p')"
    if [ "$email" != "$EXPECTED_EMAIL" ]; then
      warn "commit ${commit:0:12}: $role email '$email' does not match the configured team email '$EXPECTED_EMAIL'"
      return 1
    fi
  fi
  return 0
}

check_commit_content() {
  local commit="$1" fail=0
  local patch; patch="$(git show --format= "$commit" 2>/dev/null)"
  [ -z "$patch" ] && return 0
  local added; added="$(printf '%s\n' "$patch" | grep -E '^\+' | grep -Ev '^\+\+\+')"
  [ -z "$added" ] && return 0
  local pat
  for pat in "${SECRET_PATTERNS[@]}"; do
    if printf '%s\n' "$added" | grep -qE "$pat"; then
      warn "commit ${commit:0:12}: added content matches a known secret/token pattern ($pat) — review before pushing"
      fail=1
    fi
  done
  if [ -n "$EXPECTED_EMAIL" ]; then
    local mails; mails="$(printf '%s\n' "$added" | grep -oE '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}' | sort -u)"
    while IFS= read -r m; do
      [ -z "$m" ] && continue
      [ "$m" = "$EXPECTED_EMAIL" ] && continue
      warn "commit ${commit:0:12}: added content contains email '$m' — not the configured team email, check for a leaked private address"
      fail=1
    done <<< "$mails"
  fi
  return "$fail"
}

if [ "${1:-}" = "--self-test" ]; then
  T="$(mktemp -d "${TMPDIR:-/tmp}/pre-push-floor-selftest.XXXXXX")"
  trap 'rm -rf "$T"' EXIT
  git init -q --bare "$T/remote.git"
  git init -q "$T/work"
  git -C "$T/work" remote add origin "$T/remote.git"
  export GIT_AUTHOR_NAME="Garfield (Demo Architect)" GIT_AUTHOR_EMAIL="team@example.com"
  export GIT_COMMITTER_NAME="Garfield (Demo Architect)" GIT_COMMITTER_EMAIL="team@example.com"
  echo hi > "$T/work/f.txt"
  git -C "$T/work" add f.txt
  git -C "$T/work" commit -q -m "good identity"
  mkdir -p "$T/work/.git/hooks"
  cp "${BASH_SOURCE[0]}" "$T/work/.git/hooks/pre-push"
  chmod +x "$T/work/.git/hooks/pre-push"
  if DEV_TEAM_EMAIL=team@example.com git -C "$T/work" push -q origin HEAD:refs/heads/main 2>"$T/err1"; then
    echo "self-test 1/2 OK: canon identity → push allowed"
  else
    echo "self-test 1/2 FAIL: canon identity got blocked"; cat "$T/err1"; exit 1
  fi
  # unset statt nur überschreiben: GIT_AUTHOR_*/COMMITTER_*-Env sticht `-c user.name=` sonst aus
  # (Git-Identitäts-Reihenfolge: Env vor Config) — exakt die Env-Persistenz-Falle aus commits.md.
  env -u GIT_AUTHOR_NAME -u GIT_AUTHOR_EMAIL -u GIT_COMMITTER_NAME -u GIT_COMMITTER_EMAIL \
    git -C "$T/work" -c user.name="Some Human" -c user.email="personal@gmail.com" \
    commit -q --allow-empty -m "bad identity"
  if DEV_TEAM_EMAIL=team@example.com git -C "$T/work" push -q origin HEAD:refs/heads/main 2>"$T/err2"; then
    echo "self-test 2/2 FAIL: bad identity was NOT blocked"; exit 1
  else
    echo "self-test 2/2 OK: bad identity → push blocked"
  fi
  exit 0
fi

if [ "${BOBNET_PUSH_FLOOR_SKIP:-0}" = 1 ]; then
  warn "SKIPPED (BOBNET_PUSH_FLOOR_SKIP=1) — floor bypassed, the compliance gate still applies downstream"
  exit 0
fi

REMOTE_NAME="${1:-origin}"
fail=0

while read -r local_ref local_sha remote_ref remote_sha; do
  [ -z "${local_sha:-}" ] && continue
  [ "$local_sha" = "$ZERO_SHA" ] && continue   # branch deletion — nothing to check

  if [ "$remote_sha" = "$ZERO_SHA" ]; then
    commits="$(git rev-list "$local_sha" --not --remotes="$REMOTE_NAME" 2>/dev/null)"
  else
    commits="$(git rev-list "$remote_sha..$local_sha" 2>/dev/null)"
  fi
  [ -z "$commits" ] && continue

  while IFS= read -r commit; do
    [ -z "$commit" ] && continue
    an="$(git log -1 --format='%an <%ae>' "$commit")"
    cn="$(git log -1 --format='%cn <%ce>' "$commit")"
    check_identity "$commit" author "$an" || fail=1
    check_identity "$commit" committer "$cn" || fail=1
    check_commit_content "$commit" || fail=1
  done <<< "$commits"
done

if [ "$fail" = 1 ]; then
  warn "FLOOR TRIPPED — push blocked (ref: pushing to '$REMOTE_NAME'). This is an early warning,"
  warn "not the final judgment — the compliance gate still runs downstream. Bypass (only if you"
  warn "are SURE): BOBNET_PUSH_FLOOR_SKIP=1 git push"
  exit 1
fi
exit 0
