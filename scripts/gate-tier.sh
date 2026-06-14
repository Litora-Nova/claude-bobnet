#!/usr/bin/env bash
# scripts/gate-tier.sh — klassifiziert einen Change deterministisch in eine Merge-Gate-Stufe
# (A|B|C) anhand der GEÄNDERTEN PFADE (#32 / Welle-2 §1). Ersetzt Bauchgefühl durch Pfad-Matrix.
#
#   A — voll      : Review (Riker) + Compliance (Dexter) + Tests (Marvin) · Builder ≠ Reviewer ·
#                   NICHT self-merge-bar (Floor).
#   B — leicht    : Compliance-Spot-Check (white-label/PII) · self-merge MIT Spot-Check.
#   C — self-merge: Self-merge + Stichprobe (intern/nicht-public).
#
# Regel-Quelle (Daten vor Code): team-rules/gate-tiers.paths (Projekt-Override > Engine).
# Pro Pfad: FIRST-Match gewinnt (Liste spezifisch→generisch), kein Match → A (Floor).
# Gesamt  : HÖCHSTE Tier über alle Pfade (A>B>C) — ein Tier-A-Pfad zieht den ganzen Change auf A.
#
# Usage:
#   gate-tier.sh [--require]                 # Pfade von STDIN (eine pro Zeile)
#   gate-tier.sh [--require] --diff <base>   # Pfade aus `git diff --name-only base..HEAD`
#   gate-tier.sh --self-test
# Ausgabe (STDOUT): "gate-tier: TIER=<X> required=<roles> self_merge=<yes|no> paths=<n> ..."
#   --require: Exit 2, wenn die Stufe NICHT self-merge-bar ist (Tier A) — für Pre-Merge-Hook/Wrapper.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENGINE_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

for env_candidate in \
  "${DEV_TEAM_ENV:-}" \
  "$ENGINE_ROOT/scripts/dev-team.env" \
  "$ENGINE_ROOT/../../_dev_team/dev-team.env"; do
  [ -n "$env_candidate" ] && [ -f "$env_candidate" ] && { . "$env_candidate"; break; }
done

ENGINE_MATRIX="$ENGINE_ROOT/team-rules/gate-tiers.paths"
PROJECT_MATRIX="${PROJECT_ROOT:-}/_dev_team/team-rules/gate-tiers.paths"

# Matrix laden: Projekt-Override-Zeilen ZUERST (first-match → gewinnen), dann Engine. Kommentare/Leerzeilen raus.
load_matrix() {
  [ -n "${PROJECT_ROOT:-}" ] && [ -f "$PROJECT_MATRIX" ] && grep -vE '^[[:space:]]*(#|$)' "$PROJECT_MATRIX"
  [ -f "$ENGINE_MATRIX" ] && grep -vE '^[[:space:]]*(#|$)' "$ENGINE_MATRIX"
}

tier_rank() { case "$1" in A) echo 3;; B) echo 2;; C) echo 1;; *) echo 0;; esac; }

# classify_path PATH → Tier (first-match gegen $MATRIX; kein Match → A)
classify_path() {
  local path="$1" tier glob
  while read -r tier glob; do
    [ -z "$tier" ] && continue
    # shellcheck disable=SC2053
    if [[ "$path" == $glob ]]; then echo "$tier"; return 0; fi
  done <<< "$MATRIX"
  echo "A"
}

selftest() {
  MATRIX="$(load_matrix)"
  local fails=0 got
  check() { got="$(classify_path "$1")"; if [ "$got" = "$2" ]; then echo "  ok: $1 → $2"; else echo "  FAIL: $1 → $got (want $2)"; fails=1; fi; }
  check "scripts/gate-tier.sh"        A
  check "team-rules/x.md"             A
  check "hooks/deploy-guard.sh"       A
  check "README.md"                   B
  check "scripts/README.md"           B
  check "docs/guide.md"               B
  check "projects.registry.json"      B
  check "standup/_inbox.md"           C
  check "VERSION"                     A
  [ "$fails" = 0 ] && echo "gate-tier self-test: OK" || echo "gate-tier self-test: FAIL"
  return "$fails"
}

# --- Args ---
REQUIRE=0; MODE=stdin; DIFF_BASE=""; DIFF_HEAD="HEAD"
while [ $# -gt 0 ]; do
  case "$1" in
    --require)   REQUIRE=1; shift;;
    --diff)      MODE=diff; DIFF_BASE="${2:-}"; shift 2 || shift;;
    --self-test) selftest; exit $?;;
    -h|--help)   grep -E '^# ' "$0" | sed 's/^# //'; exit 0;;
    *) echo "gate-tier: unbekanntes Argument '$1'" >&2; exit 64;;
  esac
done

# --- geänderte Pfade beschaffen ---
if [ "$MODE" = diff ]; then
  [ -n "$DIFF_BASE" ] || { echo "gate-tier: --diff braucht <base>" >&2; exit 64; }
  PATHS="$(git diff --name-only "$DIFF_BASE..$DIFF_HEAD" 2>/dev/null)" \
    || { echo "gate-tier: 'git diff $DIFF_BASE..$DIFF_HEAD' fehlgeschlagen" >&2; exit 65; }
else
  PATHS="$(cat)"
fi

MATRIX="$(load_matrix)"
overall=""; overall_rank=0; top_path=""; n=0
while IFS= read -r p; do
  [ -z "$p" ] && continue
  n=$((n+1))
  t="$(classify_path "$p")"; r="$(tier_rank "$t")"
  printf '  %s  %s\n' "$t" "$p" >&2
  if [ "$r" -gt "$overall_rank" ]; then overall_rank="$r"; overall="$t"; top_path="$p"; fi
done <<< "$PATHS"

if [ "$n" -eq 0 ]; then
  echo "gate-tier: TIER=- required=none self_merge=yes paths=0 (keine Änderungen)"
  exit 0
fi

case "$overall" in
  A) required="review,compliance,tests"; self_merge="no";;
  B) required="compliance";              self_merge="yes";;
  C) required="none";                    self_merge="yes";;
esac

echo "gate-tier: TIER=$overall required=$required self_merge=$self_merge paths=$n (höchster: $top_path)"

if [ "$REQUIRE" = 1 ] && [ "$self_merge" = "no" ]; then
  echo "gate-tier: Tier-$overall ist NICHT self-merge-bar — voller Gate (review+compliance+tests) Pflicht." >&2
  exit 2
fi
exit 0
