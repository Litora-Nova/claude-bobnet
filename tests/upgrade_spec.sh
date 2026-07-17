#!/usr/bin/env bash
# tests/upgrade_spec.sh — Black-Box-Spec für bin/upgrade's Surface-Erkennung (Kanon-Drift-Fix
# 2026-07-17): vorher rief bin/upgrade IMMER das klassische bin/onboard auf, auch für ein rein
# codex-onboardetes Projekt — der refreshte Re-Onboard traf dann die falsche Surface.
#
# Spec-Quelle: bin/upgrade Schritt 3 — Marker sind dieselben, die die Onboarder selbst anlegen
# (bin/onboard-codex → .codex/, bin/onboard → .claude/):
#   - nur .claude/ (oder gar keine Surface-Spur)  → NUR bin/onboard.
#   - nur .codex/                                  → NUR bin/onboard-codex.
#   - beide vorhanden                              → BEIDE (idempotenter Refresh je Surface).
#
# Fixture: eine echte, minimale Engine (eigenes Git-Repo + Origin), damit bin/upgrade Schritt 1
# (git pull --ff-only) UND Schritt 2 (check-compat) real, aber offline durchlaufen — bin/onboard
# und bin/onboard-codex werden durch Marker-Stubs ersetzt (deren eigenes Verhalten ist bereits
# durch onboard_rules_spec.sh etc. abgedeckt; hier zählt NUR, welcher Onboarder aufgerufen wird).
. "$(dirname "${BASH_SOURCE[0]}")/_helper.sh"

REAL_UPGRADE="$ENGINE_ROOT/bin/upgrade"
REAL_CHECK_COMPAT="$ENGINE_ROOT/bin/check-compat"

echo "upgrade_spec:"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# --- Fake-Engine mit echtem Git-Repo + Origin (offline pull muss klappen: "Already up to date") ---
ORIGIN_BARE="$TMP/origin.git"
ENGINE="$TMP/engine"
git init --quiet --bare "$ORIGIN_BARE"
git clone --quiet "$ORIGIN_BARE" "$ENGINE" 2>/dev/null
mkdir -p "$ENGINE/bin"
cp "$REAL_UPGRADE" "$ENGINE/bin/upgrade"
cp "$REAL_CHECK_COMPAT" "$ENGINE/bin/check-compat"
printf '1\n' > "$ENGINE/SCHEMA_VERSION"
printf '0.0.0-test\n' > "$ENGINE/VERSION"

MARKER="$TMP/calls.log"
cat > "$ENGINE/bin/onboard" <<'STUB'
#!/usr/bin/env bash
echo "onboard $*" >> "$MARKER"
STUB
cat > "$ENGINE/bin/onboard-codex" <<'STUB'
#!/usr/bin/env bash
echo "onboard-codex $*" >> "$MARKER"
STUB
chmod +x "$ENGINE/bin/upgrade" "$ENGINE/bin/check-compat" "$ENGINE/bin/onboard" "$ENGINE/bin/onboard-codex"

git -C "$ENGINE" config user.email test@example.com
git -C "$ENGINE" config user.name "Test"
git -C "$ENGINE" add -A
git -C "$ENGINE" commit --quiet -m "fake engine fixture"
git -C "$ENGINE" push --quiet origin HEAD 2>/dev/null || git -C "$ENGINE" push --quiet -u origin "$(git -C "$ENGINE" rev-parse --abbrev-ref HEAD)"

# matching dev-team.env so check-compat passes cleanly (ENGINE_SCHEMA == SCHEMA_VERSION).
mk_project() { # $1 = project dir
  mkdir -p "$1/_dev_team"
  printf 'export ENGINE_SCHEMA="1"\n' > "$1/_dev_team/dev-team.env"
}

run_upgrade() { # $1 = project dir → setzt UPGRADE_RC, leert+füllt MARKER
  : > "$MARKER"
  MARKER="$MARKER" bash "$ENGINE/bin/upgrade" "$1" >/dev/null 2>"$TMP/stderr"
  UPGRADE_RC=$?
}

# --- Nur .claude/ (klassisch onboardetes Projekt) → NUR bin/onboard ---
P_CLASSIC="$TMP/proj-classic"; mkdir -p "$P_CLASSIC/.claude"; mk_project "$P_CLASSIC"
run_upgrade "$P_CLASSIC"
it "classic-only: Exit 0";                       eq "$UPGRADE_RC" "0"
it "classic-only: bin/onboard aufgerufen";       contains "$(cat "$MARKER")" "onboard $P_CLASSIC"
it "classic-only: bin/onboard-codex NICHT aufgerufen"; not_contains "$(cat "$MARKER")" "onboard-codex"

# --- Nur .codex/ (rein codex-onboardetes Projekt) → NUR bin/onboard-codex ---
P_CODEX="$TMP/proj-codex"; mkdir -p "$P_CODEX/.codex"; mk_project "$P_CODEX"
run_upgrade "$P_CODEX"
it "codex-only: Exit 0";                         eq "$UPGRADE_RC" "0"
it "codex-only: bin/onboard-codex aufgerufen";   contains "$(cat "$MARKER")" "onboard-codex $P_CODEX"
it "codex-only: klassisches bin/onboard NICHT aufgerufen (Kanon-Drift-Fix)"; not_contains "$(cat "$MARKER")" "onboard $P_CODEX"

# --- Beide Surfaces vorhanden → BEIDE Onboarder laufen ---
P_BOTH="$TMP/proj-both"; mkdir -p "$P_BOTH/.claude" "$P_BOTH/.codex"; mk_project "$P_BOTH"
run_upgrade "$P_BOTH"
it "dual-surface: Exit 0";                       eq "$UPGRADE_RC" "0"
it "dual-surface: bin/onboard aufgerufen";       contains "$(cat "$MARKER")" "onboard $P_BOTH"
it "dual-surface: bin/onboard-codex aufgerufen"; contains "$(cat "$MARKER")" "onboard-codex $P_BOTH"

# --- Keine Surface-Spur (z. B. Upgrade vor dem allerersten Onboard) → Default bleibt klassisch ---
P_FRESH="$TMP/proj-fresh"; mkdir -p "$P_FRESH"; mk_project "$P_FRESH"
run_upgrade "$P_FRESH"
it "keine Surface-Spur: Exit 0";                 eq "$UPGRADE_RC" "0"
it "keine Surface-Spur: Default = bin/onboard";  contains "$(cat "$MARKER")" "onboard $P_FRESH"
it "keine Surface-Spur: bin/onboard-codex NICHT aufgerufen"; not_contains "$(cat "$MARKER")" "onboard-codex"

summary
