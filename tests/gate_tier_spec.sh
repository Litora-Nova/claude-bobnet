#!/usr/bin/env bash
# tests/gate_tier_spec.sh — Black-Box-Spec für scripts/gate-tier.sh (Merge-Gate-Stufung, #32).
#
# Hermetisch: Pfade kommen über STDIN (kein git nötig). Geprüft wird das dokumentierte Verhalten:
# Pfad→Tier-Klassifikation (first-match, Floor A), Gesamt = höchste Tier, Rollen/self_merge je Tier,
# --require-Exit-Code, und der Projekt-Override (first-match-Vorrang).
set -uo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/_helper.sh"

GT="$SCRIPTS/gate-tier.sh"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
EMPTY_ENV="$TMP/empty.env"; : > "$EMPTY_ENV"

run_gt() { # $1 = Pfade (mit \n) · $2 = Flags (optional) → setzt GT_OUT + GT_RC
  GT_OUT="$(printf '%b' "$1" | DEV_TEAM_ENV="$EMPTY_ENV" bash "$GT" ${2:-} 2>/dev/null)"; GT_RC=$?
}

echo "gate_tier_spec:"

it "gate-tier.sh existiert + ausführbar"; ok test -x "$GT"

# --- Tier A: Code/Verhalten ---
run_gt "scripts/x.sh\n"
it "scripts/ → TIER A";                         contains "$GT_OUT" "TIER=A"
it "Tier A → required review,compliance,tests"; contains "$GT_OUT" "required=review,compliance,tests"
it "Tier A → self_merge=no";                    contains "$GT_OUT" "self_merge=no"

# --- Tier B: public Docs + non-behavior config ---
run_gt "README.md\n"
it "README → TIER B";                contains "$GT_OUT" "TIER=B"
it "Tier B → required compliance";   contains "$GT_OUT" "required=compliance"
it "Tier B → self_merge=yes";        contains "$GT_OUT" "self_merge=yes"

# --- Tier C: intern/non-public ---
run_gt "standup/_inbox.md\n"
it "standup → TIER C";        contains "$GT_OUT" "TIER=C"
it "Tier C → self_merge=yes"; contains "$GT_OUT" "self_merge=yes"

# --- Auflösungs-Feinheiten (Ordering der Matrix) ---
run_gt "team-rules/x.md\n"
it "team-rules/*.md → A (harte Regeln, nicht B trotz .md)"; contains "$GT_OUT" "TIER=A"
run_gt "scripts/README.md\n"
it "README unter scripts/ → B (Docs vor Code-Dir per First-Match)"; contains "$GT_OUT" "TIER=B"

# --- Gesamt = höchste Tier über alle Pfade ---
run_gt "README.md\nscripts/x.sh\n"
it "gemischt A+B → A (höchste gewinnt)"; contains "$GT_OUT" "TIER=A"
run_gt "docs/a.md\nstandup/foo.log\n"
it "gemischt B+C → B (höchste gewinnt)"; contains "$GT_OUT" "TIER=B"

# --- Floor + leere Eingabe ---
run_gt "voellig/fremd.xyz\n"
it "unbekannter Pfad → A (konservativer Floor)"; contains "$GT_OUT" "TIER=A"
run_gt "\n"
it "leere Eingabe → paths=0"; contains "$GT_OUT" "paths=0"
it "leere Eingabe → Exit 0";  eq "$GT_RC" "0"

# --- --require erzwingt den Floor (Tier A nicht self-merge-bar) ---
run_gt "scripts/x.sh\n" "--require"
it "--require auf Tier A → Exit 2"; eq "$GT_RC" "2"
run_gt "standup/x\n" "--require"
it "--require auf Tier C → Exit 0"; eq "$GT_RC" "0"
run_gt "README.md\n" "--require"
it "--require auf Tier B → Exit 0 (self-merge-bar)"; eq "$GT_RC" "0"

# --- Projekt-Override: hebt einen Pfad an (first-match-Vorrang, nur verschärfen) ---
PROJ="$TMP/proj"; mkdir -p "$PROJ/_dev_team/team-rules"
printf 'A *config/danger/*\n' > "$PROJ/_dev_team/team-rules/gate-tiers.paths"
GT_OUT="$(printf 'config/danger/x.yml\n' | DEV_TEAM_ENV="$EMPTY_ENV" PROJECT_ROOT="$PROJ" bash "$GT" 2>/dev/null)"
it "Projekt-Override hebt config/danger/ auf A"; contains "$GT_OUT" "TIER=A"
# ohne Override wäre config/danger/x.yml → A (Floor, kein Match) — Gegenprobe mit B-Override:
printf 'B *config/danger/*\n' > "$PROJ/_dev_team/team-rules/gate-tiers.paths"
GT_OUT="$(printf 'config/danger/x.yml\n' | DEV_TEAM_ENV="$EMPTY_ENV" PROJECT_ROOT="$PROJ" bash "$GT" 2>/dev/null)"
it "Override greift wirklich (B-Override → TIER B statt Floor-A)"; contains "$GT_OUT" "TIER=B"

# --- Self-Test des Scripts ---
it "--self-test Exit 0 (script-interne Sanity)"; ok bash "$GT" --self-test

summary
