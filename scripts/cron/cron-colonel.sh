#!/usr/bin/env bash
# Colonel-Watch (cron): macht den Colonel "permanent" (PLAN §F — "Colonel = Mario, permanent").
#
# Dünner Cron-Wrapper, der `scripts/colonel.sh --run` ONE-SHOT läuft, das Resultat in den
# standup-Bereich loggt (`Colonel.log`, analog wie cron-bugcheck nach `_bugs.md` appendet) und bei
# Disziplin-Bruch (✗ → Exit 1) bzw. Warnungen (⚠) via SCUT meldet — über das BESTEHENDE
# scripts/scut.sh, NICHT neu gebaut. Colonel selbst ist die Mechanik (ein Lauf = ein Report);
# dieses Script ist nur das WANN (der Scheduler-Eintrag, siehe colonel.sh Header "Schedule-Mechanik").
#
# ── Vorgeschlagene crontab-Zeile (NICHT hier installiert — Live-Cron = Austins T4-Checkpoint) ──────
#   Alle 45 min (PLAN: "alle 30–60 min gedacht"), Zeit = Europe/Berlin (CRON_TZ), Sammel-Log ~/cron.log:
#
#     */45 * * * * $HOME/Sites/<engine>/scripts/cron/cron-colonel.sh >> ~/cron.log 2>&1
#
#   (Pfad an den Engine-Root anpassen; analog den anderen cron/-Jobs. crontab-Aktivierung macht
#    Austin via `crontab -e` — siehe scripts/cron/README.md "Verwaltung".)
#
# ── Env (geerbt aus dev-team.env, falls auffindbar — sonst Defaults) ───────────────────────────────
#   DEV_TEAM_ENV      expliziter Pfad zur dev-team.env (Override). Sonst Auto-Suche (s.u.).
#   PROJECT_ROOT      Repo-Root des Projekts (für STANDUP_DIR/Env-Auflösung).
#   STANDUP_DIR       Heartbeat-/Inbox-/Log-Ordner (Default: <ROOT>/standup). Ziel von Colonel.log.
#   TEAM_LEAD         Team-Lead-Name (an colonel.sh durchgereicht für die Commit-Heuristik).
#   COLONEL_BIN       Pfad zu colonel.sh (Default: <ROOT>/scripts/colonel.sh). Test-Override.
#   SCUT_BIN          Pfad zu scut.sh (Default: <STANDUP_DIR>/scut.sh ODER <ROOT>/scripts/scut.sh).
#   COLONEL_WARN_PING 1 = bei ⚠ (ohne ✗) einen 🟡 mid-SCUT senden; 0 = nur ✗ pingt. Default 1.
#   DEV_TEAM_TZ       Zeitzone (Default Europe/Berlin).
#   --self-test       Dry-Run mit Stubs (KEIN echter colonel/scut/cron-Effekt) + Logik-Checks.
#
# Exit:  spiegelt colonel.sh — 0 = alle Checks ✓/⊘ | 1 = mindestens ein ✗ (Disziplin-Bruch).
set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$DIR/../.." && pwd)"

# ── dev-team.env sourcen (falls auffindbar) ────────────────────────────────────────────────────────
# Cron startet ohne Projekt-Env; wir holen PROJECT_ROOT/STANDUP_DIR/TEAM_LEAD/BOBNET_URL/… daher hier.
# Reihenfolge: $DEV_TEAM_ENV (explizit) > $PROJECT_ROOT/_dev_team/dev-team.env > Geschwister-Lookup
# neben dem Engine-Root (Engine wohnt typ. in <toolhub>/, Projekt-Env im Projekt-Repo).
source_env() {
  local cand=""
  for cand in \
    "${DEV_TEAM_ENV:-}" \
    "${PROJECT_ROOT:-}/_dev_team/dev-team.env" \
    "${PROJECT_ROOT:-}/dev-team.env" \
    "$ROOT/_dev_team/dev-team.env" \
    "$ROOT/dev-team.env"
  do
    [ -n "$cand" ] && [ -f "$cand" ] || continue
    # shellcheck disable=SC1090
    set -a; . "$cand"; set +a
    DEV_TEAM_ENV="$cand"   # für den Report sichtbar machen
    return 0
  done
  return 1
}
source_env || true

ST="${STANDUP_DIR:-$ROOT/standup}"
LEAD="${TEAM_LEAD:-Bob}"
COLONEL_BIN="${COLONEL_BIN:-$ROOT/scripts/colonel.sh}"
WARN_PING="${COLONEL_WARN_PING:-1}"
TZc="${DEV_TEAM_TZ:-Europe/Berlin}"

# scut.sh: bevorzugt im standup-Bereich (alte Projekt-Struktur), sonst im Engine-scripts-Ordner.
resolve_scut() {
  if [ -n "${SCUT_BIN:-}" ]; then printf '%s' "$SCUT_BIN"; return; fi
  if [ -x "$ST/scut.sh" ]; then printf '%s' "$ST/scut.sh"; return; fi
  if [ -x "$ROOT/scripts/scut.sh" ]; then printf '%s' "$ROOT/scripts/scut.sh"; return; fi
  printf ''   # kein scut auffindbar → still (Log bleibt, kein Ping)
}

# ── Ein Colonel-Lauf, Report loggen, melden ────────────────────────────────────────────────────────
run_colonel() {
  # Per-Call aus der Env auflösen (NICHT die Load-Zeit-Globals) — so greifen Overrides aus
  # dev-team.env UND aus dem Self-Test (STANDUP_DIR/COLONEL_WARN_PING/TEAM_LEAD/COLONEL_BIN).
  local ST="${STANDUP_DIR:-$ROOT/standup}"
  local LEAD="${TEAM_LEAD:-Bob}"
  local COLONEL_BIN="${COLONEL_BIN:-$ROOT/scripts/colonel.sh}"
  local WARN_PING="${COLONEL_WARN_PING:-1}"
  local ts; ts="$(TZ="$TZc" date '+%Y-%m-%d %H:%M' 2>/dev/null || date '+%Y-%m-%d %H:%M')"

  if [ ! -x "$COLONEL_BIN" ] && [ ! -f "$COLONEL_BIN" ]; then
    echo "[colonel] FEHLER: colonel.sh nicht gefunden ($COLONEL_BIN)"
    local scut; scut="$(resolve_scut)"
    [ -n "$scut" ] && "$scut" "Colonel-Watch $ts: colonel.sh fehlt ($COLONEL_BIN) — Scheduler defekt" urgent >/dev/null 2>&1
    return 1
  fi

  # colonel.sh --run produziert den Report (✓/⚠/✗-Zeilen + "--- Colonel: N ✗ / M ⚠ ---") und
  # einen sprechenden Exit-Code. Output einsammeln, NICHT verschlucken.
  local out rc
  out="$(TEAM_LEAD="$LEAD" STANDUP_DIR="$ST" bash "$COLONEL_BIN" --run 2>&1)"; rc=$?

  # ✗/⚠-Zähler aus der Summenzeile ziehen (robust: Fallback 0, falls Format-Drift).
  local fails warns
  fails="$(printf '%s\n' "$out" | sed -n 's/.*--- Colonel: \([0-9]\{1,\}\) ✗.*/\1/p' | tail -n1)"
  warns="$(printf '%s\n' "$out" | sed -n 's/.*--- Colonel: [0-9]\{1,\} ✗ \/ \([0-9]\{1,\}\) ⚠.*/\1/p' | tail -n1)"
  fails="${fails:-0}"; warns="${warns:-0}"

  # In den standup-Bereich loggen (append, mit Trennzeile — wie cron-bugcheck nach _bugs.md).
  mkdir -p "$ST"
  {
    printf '## Colonel-Audit %s (exit %s, %s ✗ / %s ⚠)\n' "$ts" "$rc" "$fails" "$warns"
    printf '%s\n\n' "$out"
  } >> "$ST/Colonel.log"

  # Melden via bestehendes scut.sh: ✗ → 🔴 urgent; nur-⚠ → 🟡 mid (wenn WARN_PING=1); sonst still.
  local scut; scut="$(resolve_scut)"
  if [ -n "$scut" ]; then
    if [ "$rc" -ne 0 ] || [ "$fails" -gt 0 ]; then
      "$scut" "Colonel $ts: $fails Disziplin-Bruch(✗), $warns ⚠ — siehe Colonel.log" urgent >/dev/null 2>&1
    elif [ "$warns" -gt 0 ] && [ "$WARN_PING" = "1" ]; then
      "$scut" "Colonel $ts: $warns ⚠ (kein Bruch) — siehe Colonel.log" mid >/dev/null 2>&1
    fi
  fi

  echo "[colonel] $( [ "$rc" -eq 0 ] && echo ok || echo FAIL ) $ts (exit=$rc fails=$fails warns=$warns)"
  return "$rc"
}

# ── Self-Test: Dry-Run mit Stubs — KEIN echter colonel/scut/cron-Effekt ──────────────────────────────
self_test() {
  local tmp; tmp="$(mktemp -d "${TMPDIR:-/tmp}/cron-colonel-test.XXXXXX")"
  trap "rm -rf '$tmp'" EXIT
  local fail=0
  check() { if eval "$2"; then printf '  ✓ %s\n' "$3"; else printf '  ✗ %s\n' "$3"; fail=1; fi; }

  # Stub-colonel: emittiert einen realistischen Report + steuerbaren Exit/Zähler via Env.
  local stub_colonel="$tmp/colonel.sh"
  cat > "$stub_colonel" <<'STUB'
#!/usr/bin/env bash
echo "=== Colonel — Disziplin-Audit (stub) ==="
echo "  ✓ stub-check"
echo "--- Colonel: ${STUB_FAILS:-0} ✗ / ${STUB_WARNS:-0} ⚠ ---"
exit "${STUB_RC:-0}"
STUB
  chmod +x "$stub_colonel"

  # Stub-scut: schreibt jeden Aufruf in eine Datei statt zu telegrammen (Effekt-frei, prüfbar).
  local stub_scut="$tmp/scut.sh" scut_log="$tmp/scut.calls"
  cat > "$stub_scut" <<STUB
#!/usr/bin/env bash
printf '%s | %s\n' "\${2:-info}" "\$1" >> "$scut_log"
STUB
  chmod +x "$stub_scut"

  local st="$tmp/standup"; mkdir -p "$st"

  # Lauf 1: clean (rc=0, 0✗/0⚠) → Exit 0, Log geschrieben, KEIN scut-Call.
  rm -f "$scut_log"
  STUB_RC=0 STUB_FAILS=0 STUB_WARNS=0 \
    COLONEL_BIN="$stub_colonel" SCUT_BIN="$stub_scut" STANDUP_DIR="$st" \
    run_colonel >/dev/null 2>&1
  local rc1=$?
  check x "[ $rc1 -eq 0 ]" "clean-Lauf: Exit 0 (war $rc1)"
  check x "[ -f \"$st/Colonel.log\" ]" "clean-Lauf: Colonel.log geschrieben"
  check x "[ ! -f \"$scut_log\" ]" "clean-Lauf: KEIN scut-Ping (kein ✗/⚠)"

  # Lauf 2: nur Warnungen (rc=0, 2⚠) → Exit 0, 🟡 mid-Ping (WARN_PING=1 default).
  rm -f "$scut_log"
  STUB_RC=0 STUB_FAILS=0 STUB_WARNS=2 \
    COLONEL_BIN="$stub_colonel" SCUT_BIN="$stub_scut" STANDUP_DIR="$st" COLONEL_WARN_PING=1 \
    run_colonel >/dev/null 2>&1
  local rc2=$?
  check x "[ $rc2 -eq 0 ]" "warn-Lauf: Exit 0 trotz ⚠ (war $rc2)"
  check x "[ -f \"$scut_log\" ] && grep -q '^mid ' \"$scut_log\"" "warn-Lauf: 🟡 mid-Ping gesendet"

  # Lauf 2b: Warnungen, aber WARN_PING=0 → KEIN Ping.
  rm -f "$scut_log"
  STUB_RC=0 STUB_FAILS=0 STUB_WARNS=2 \
    COLONEL_BIN="$stub_colonel" SCUT_BIN="$stub_scut" STANDUP_DIR="$st" COLONEL_WARN_PING=0 \
    run_colonel >/dev/null 2>&1
  check x "[ ! -f \"$scut_log\" ]" "warn-Lauf + WARN_PING=0: KEIN Ping"

  # Lauf 3: Disziplin-Bruch (rc=1, 1✗) → Exit 1, 🔴 urgent-Ping.
  rm -f "$scut_log"
  STUB_RC=1 STUB_FAILS=1 STUB_WARNS=0 \
    COLONEL_BIN="$stub_colonel" SCUT_BIN="$stub_scut" STANDUP_DIR="$st" \
    run_colonel >/dev/null 2>&1
  local rc3=$?
  check x "[ $rc3 -eq 1 ]" "bruch-Lauf: Exit 1 (war $rc3)"
  check x "[ -f \"$scut_log\" ] && grep -q '^urgent ' \"$scut_log\"" "bruch-Lauf: 🔴 urgent-Ping gesendet"

  # Lauf 4: colonel.sh fehlt → Exit 1 + urgent-Ping (Scheduler-Selbstschutz).
  rm -f "$scut_log"
  COLONEL_BIN="$tmp/nonexistent-colonel.sh" SCUT_BIN="$stub_scut" STANDUP_DIR="$st" \
    run_colonel >/dev/null 2>&1
  local rc4=$?
  check x "[ $rc4 -eq 1 ]" "fehlend-Lauf: Exit 1 wenn colonel.sh weg (war $rc4)"
  check x "[ -f \"$scut_log\" ] && grep -q '^urgent ' \"$scut_log\"" "fehlend-Lauf: 🔴 urgent-Ping"

  # Lauf 5: kein scut auffindbar → kein Crash, Log trotzdem da.
  rm -f "$st/Colonel.log"
  STUB_RC=1 STUB_FAILS=1 STUB_WARNS=0 \
    COLONEL_BIN="$stub_colonel" SCUT_BIN="$tmp/no-scut.sh" STANDUP_DIR="$st" \
    run_colonel >/dev/null 2>&1
  local rc5=$?
  check x "[ $rc5 -eq 1 ]" "kein-scut-Lauf: Exit spiegelt colonel (war $rc5)"
  check x "[ -f \"$st/Colonel.log\" ]" "kein-scut-Lauf: Log dennoch geschrieben (kein Ping nötig)"

  if [ "$fail" = 0 ]; then echo "cron-colonel self-test: GRÜN"; return 0
  else echo "cron-colonel self-test: ROT"; return 1; fi
}

case "${1:-}" in
  --self-test|self-test) self_test; exit $? ;;
  ""|--run|run)          run_colonel; exit $? ;;
  -h|--help)             sed -n '2,40p' "${BASH_SOURCE[0]}"; exit 0 ;;
  *) echo "Usage: cron-colonel.sh [--run] | cron-colonel.sh --self-test | cron-colonel.sh --help" >&2; exit 64 ;;
esac
