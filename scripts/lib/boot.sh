#!/usr/bin/env bash
# boot.sh — mux_boot: einen Lead HEADLESS hochfahren + per Inbox briefen (Inbox-first-Boot, Issue #35).
#
# Warum (#35): zellij `run`/Spawn LÄUFT headless (ohne attached Client), aber `write-chars`/
# `dump-screen` NICHT — ein clientloses Pane wird nicht gerendert/getrieben. Deshalb wird ein
# Lead NICHT per Keystroke gebrieft, sondern: (1) via mux_spawn gestartet (headless ✓) und
# (2) das Briefing in die Ziel-Inbox gedroppt. Der SessionStart-Hook zieht Sync+Inbox beim Boot,
# der Lead liest sich selbst ein. Liveness läuft über Heartbeat/BobNet, nicht über dump-screen.
#
# Schicht: GENERISCHE Engine-Mechanik. Die Boot-/Host-Doktrin (Orchestrierungs-Ebene) ruft mux_boot
# mit IHREN konkreten Pfaden auf — boot.sh kennt KEINE projekt-spezifischen Pfade (Daten vor Code).
#
# Usage (sourcen ODER direkt ausführen):
#   mux_boot SESSION START_CMD [BRIEFING]
#     SESSION    Multiplexer-Session-Name (i. d. R. der Lead-/Folder-Name).
#     START_CMD  self-contained Start-Command für den Lead (läuft als Pane, headless).
#     BRIEFING   optionaler Briefing-Text → wird @-adressiert in die Ziel-Inbox gedroppt.
#   Env:
#     BOOT_INBOX  Ziel-Inbox-Datei (Default: $STANDUP_DIR/_inbox.md).
#     BOOT_TO     Adressat im Briefing (Default: SESSION).
#     BOOT_FROM   Absender-Signatur im Briefing (Default: "boot").
#   Verhalten:
#     - Idempotent: läuft die Session schon (mux_has) → KEIN Re-Spawn UND KEIN Re-Briefing (rc 0).
#     - Reihenfolge: erst Briefing droppen, DANN spawnen — sonst Race (Lead liest die Inbox,
#       bevor das Briefing drin ist).
#     - Kein BRIEFING / keine erreichbare Inbox → nur spawnen (Briefing still übersprungen).
#     - rc = rc von mux_spawn (Spawn-Fehler propagiert); fehlende SESSION → rc 2.
set -uo pipefail

_BOOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$_BOOT_DIR/mux.sh"

mux_boot() {
  local session="${1:-}" start_cmd="${2:-}" briefing="${3:-}"
  [ -n "$session" ] || { echo "mux_boot: SESSION fehlt" >&2; return 2; }

  # Idempotent: läuft schon → nichts tun (kein Doppel-Spawn, kein Doppel-Briefing).
  if mux_has "$session" 2>/dev/null; then
    echo "mux_boot: '$session' läuft bereits — idempotent übersprungen" >&2
    return 0
  fi

  # Briefing ZUERST in die Inbox (vor dem Spawn → kein Race mit dem SessionStart-Inbox-Pull).
  if [ -n "$briefing" ]; then
    local inbox="${BOOT_INBOX:-${STANDUP_DIR:-}/_inbox.md}"
    local to="${BOOT_TO:-$session}" from="${BOOT_FROM:-boot}"
    if [ "$inbox" != "/_inbox.md" ] && { [ -f "$inbox" ] || [ -d "$(dirname "$inbox")" ]; }; then
      printf '%s | @%s | %s — (%s)\n' "$(date '+%Y-%m-%d %H:%M')" "$to" "$briefing" "$from" >> "$inbox" \
        || echo "mux_boot: WARN konnte Briefing nicht nach '$inbox' schreiben" >&2
    else
      echo "mux_boot: WARN keine Ziel-Inbox (BOOT_INBOX/STANDUP_DIR) — Briefing übersprungen" >&2
    fi
  fi

  # Lead headless starten (mux_spawn: zellij `run` / tmux `new-session -d`).
  mux_spawn "$session" "$start_cmd"
}

# Direkt ausführbar: boot.sh SESSION START_CMD [BRIEFING]  (für die Boot-Doktrin/CLI).
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  mux_boot "$@"
fi
