#!/usr/bin/env bash
# tests/cron_colonel_spec.sh — Behavior-Spec für scripts/cron/cron-colonel.sh.
#
# SPEC-Quelle: cron-colonel.sh-Header + PLAN_bobiverse.md §F ("Colonel = Mario, permanent").
#   cron-colonel.sh ist ein dünner Cron-Wrapper um `scripts/colonel.sh --run`:
#     • ruft colonel.sh --run one-shot, sammelt dessen Report (✓/⚠/✗ + Summenzeile),
#     • appendet einen Audit-Block nach <STANDUP_DIR>/Colonel.log (analog cron-bugcheck → _bugs.md),
#     • meldet via BESTEHENDES scut.sh:  ✗/Exit≠0 → 🔴 urgent ; nur-⚠ → 🟡 mid (wenn COLONEL_WARN_PING=1),
#       sonst still,
#     • Exit-Code spiegelt colonel.sh (0 = ✓/⊘, 1 = ✗-Bruch); fehlt colonel.sh → Exit 1 + urgent.
#   KEINE crontab-Aktivierung (Live-Cron = human/T4). Baut scut/colonel NICHT neu — referenziert sie.
#
# Black-Box: Stub-colonel (steuerbarer Exit/Zähler via Env) + Stub-scut (loggt Calls statt Telegram)
#   + Wegwerf-standup in mktemp -d. NIE echtes colonel/scut/Telegram/standup angefasst.

set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_helper.sh
. "$HERE/_helper.sh"

CRON_COLONEL="$SCRIPTS/cron/cron-colonel.sh"

echo "cron-colonel.sh — Behavior-Spec"

TMP="$(mktemp -d "${TMPDIR:-/tmp}/cron-colonel-spec.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
ST="$TMP/standup"; mkdir -p "$ST"

# Stub-colonel: emittiert realistischen Report + steuerbaren Exit/Zähler via Env (STUB_RC/FAILS/WARNS).
STUB_COLONEL="$TMP/colonel.sh"
cat > "$STUB_COLONEL" <<'STUB'
#!/usr/bin/env bash
echo "=== Colonel — Disziplin-Audit (stub) ==="
echo "  ✓ stub-check"
echo "--- Colonel: ${STUB_FAILS:-0} ✗ / ${STUB_WARNS:-0} ⚠ ---"
exit "${STUB_RC:-0}"
STUB
chmod +x "$STUB_COLONEL"

# Stub-scut: schreibt jeden Call als "<level> | <msg>" in eine Datei (effekt-frei, prüfbar).
STUB_SCUT="$TMP/scut.sh"; SCUT_LOG="$TMP/scut.calls"
cat > "$STUB_SCUT" <<STUB
#!/usr/bin/env bash
printf '%s | %s\n' "\${2:-info}" "\$1" >> "$SCUT_LOG"
STUB
chmod +x "$STUB_SCUT"

LOG="$ST/Colonel.log"

# run <rc> <fails> <warns> [extra-env...] : ein Wrapper-Lauf mit Stubs; gibt Wrapper-Exit zurück.
run() {
  local rc="$1" fails="$2" warns="$3"; shift 3
  STUB_RC="$rc" STUB_FAILS="$fails" STUB_WARNS="$warns" \
    COLONEL_BIN="$STUB_COLONEL" SCUT_BIN="$STUB_SCUT" STANDUP_DIR="$ST" "$@" \
    bash "$CRON_COLONEL" --run >/dev/null 2>&1
}

# ── 1) clean (0✗/0⚠, rc=0) → Exit 0, Log geschrieben, KEIN Ping ───────────────────────────────
rm -f "$LOG" "$SCUT_LOG"
it "clean-Lauf: Wrapper-Exit 0 (spiegelt colonel)"
ok run 0 0 0
it "clean-Lauf: Colonel.log existiert + enthält Audit-Header"
file_has "$LOG" "Colonel-Audit"
it "clean-Lauf: Report-Inhalt (Summenzeile) im Log gelandet"
file_has "$LOG" "--- Colonel: 0 ✗ / 0 ⚠ ---"
it "clean-Lauf: KEIN scut-Ping (kein ✗/⚠)"
file_missing "$SCUT_LOG"

# ── 2) nur Warnungen (2⚠, rc=0) → Exit 0, 🟡 mid-Ping (WARN_PING default 1) ────────────────────
rm -f "$SCUT_LOG"
it "warn-Lauf: Exit 0 trotz ⚠ (⚠ ist kein Bruch)"
ok run 0 0 2
it "warn-Lauf: genau ein scut-Call auf Level 'mid'"
file_has "$SCUT_LOG" "mid | "
it "warn-Lauf: KEIN urgent-Call"
not_contains "$(cat "$SCUT_LOG")" "urgent | "

# ── 2b) Warnungen + COLONEL_WARN_PING=0 → KEIN Ping ───────────────────────────────────────────
rm -f "$SCUT_LOG"
it "warn-Lauf + WARN_PING=0: KEIN Ping (Schwelle abschaltbar)"
run 0 0 2 COLONEL_WARN_PING=0
file_missing "$SCUT_LOG"

# ── 3) Disziplin-Bruch (1✗, rc=1) → Exit 1, 🔴 urgent-Ping ────────────────────────────────────
rm -f "$SCUT_LOG"
it "bruch-Lauf: Wrapper-Exit 1 (spiegelt colonel-✗)"
not_ok run 1 1 0
it "bruch-Lauf: 🔴 urgent-Ping gesendet"
file_has "$SCUT_LOG" "urgent | "

# ── 3b) Exit≠0 trotz 0 gezählter ✗ (Format-Drift-Schutz) → urgent ────────────────────────────
rm -f "$SCUT_LOG"
it "rc=1 aber 0✗ geparst: trotzdem urgent (Exit-Code ist die Wahrheit)"
not_ok run 1 0 0
file_has "$SCUT_LOG" "urgent | "

# ── 4) colonel.sh fehlt → Exit 1 + urgent (Scheduler-Selbstschutz, baut nichts neu) ──────────
rm -f "$SCUT_LOG"
it "fehlende colonel.sh: Wrapper-Exit 1"
not_ok env COLONEL_BIN="$TMP/nonexistent-colonel.sh" SCUT_BIN="$STUB_SCUT" STANDUP_DIR="$ST" \
  bash "$CRON_COLONEL" --run
it "fehlende colonel.sh: 🔴 urgent-Ping (Scheduler defekt gemeldet)"
file_has "$SCUT_LOG" "urgent | "

# ── 5) kein scut auffindbar → kein Crash, Log dennoch geschrieben ─────────────────────────────
rm -f "$LOG"
it "kein scut: Wrapper crasht nicht, Exit spiegelt colonel (1)"
not_ok env COLONEL_BIN="$STUB_COLONEL" STUB_RC=1 STUB_FAILS=1 SCUT_BIN="$TMP/no-scut.sh" STANDUP_DIR="$ST" \
  bash "$CRON_COLONEL" --run
it "kein scut: Colonel.log trotzdem geschrieben (Logging ≠ Melden)"
file_has "$LOG" "Colonel-Audit"

# ── 6) Log appendet (Audit-Trail, nicht überschreiben — wie cron-bugcheck/_bugs.md) ──────────
rm -f "$LOG" "$SCUT_LOG"
it "zwei Läufe → zwei Audit-Header im Log (append, kein Truncate)"
run 0 0 0
run 0 0 0
eq "$(grep -c 'Colonel-Audit' "$LOG")" "2"

# ── 7) Usage / Self-Test ──────────────────────────────────────────────────────────────────────
it "unbekanntes Subcommand → rc!=0 (Usage)"
not_ok bash "$CRON_COLONEL" bogus-subcommand
it "--help → rc==0 (Header-Auszug)"
ok bash "$CRON_COLONEL" --help
it "mitgelieferter --self-test läuft GRÜN durch (Dry-Run mit Stubs, kein echter Effekt)"
ok bash "$CRON_COLONEL" --self-test

summary
