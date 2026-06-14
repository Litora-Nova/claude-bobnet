#!/usr/bin/env bash
# tests/boot_spec.sh — Black-Box-Spec für scripts/lib/boot.sh (mux_boot, Inbox-first-Boot, #35).
#
# Hermetisch: das NEUE Verhalten von mux_boot (Inbox-Drop, Drop-first-Reihenfolge, Idempotenz,
# Format) wird mit GESTUBBTER mux-Mechanik geprüft — kein echtes Spawnen (das deckt mux_spec.sh
# ab). Stub-Trick: boot.sh in einer Subshell sourcen, dann mux_has/mux_spawn überschreiben
# (spätere Definition gewinnt), dann mux_boot rufen.
set -uo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/_helper.sh"

BOOT="$SCRIPTS/lib/boot.sh"

it "boot.sh existiert"
ok test -f "$BOOT"

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
INBOX="$TMP/_inbox.md"
SPAWN="$TMP/spawn.trace"

echo "boot_spec:"

# --- 1) Frischer Boot: spawnt + droppt Briefing (@adressiert, mit Text + Absender) ---
: > "$INBOX"; : > "$SPAWN"
(
  . "$BOOT" 2>/dev/null
  mux_has()   { return 1; }                                   # läuft noch nicht
  mux_spawn() { printf 'SPAWN|%s|%s\n' "$1" "$2" >> "$SPAWN"; return 0; }
  STANDUP_DIR="$TMP" BOOT_FROM="garfield" \
    mux_boot "acme_bob" "cd /x && claude" "Boot: lies NEXT_SESSION + sync"
)
it "frischer Boot ruft mux_spawn mit Session+Start";  file_has "$SPAWN" "SPAWN|acme_bob|cd /x && claude"
it "frischer Boot droppt Briefing (@adressiert an Session)"; file_has "$INBOX" "@acme_bob"
it "Briefing trägt den Text";                          file_has "$INBOX" "Boot: lies NEXT_SESSION + sync"
it "Briefing trägt den Absender (BOOT_FROM)";          file_has "$INBOX" "(garfield)"

# --- 2) Drop-first: zum Zeitpunkt des Spawns ist das Briefing schon in der Inbox (kein Race) ---
: > "$INBOX"
ORDER="$(
  . "$BOOT" 2>/dev/null
  mux_has()   { return 1; }
  mux_spawn() { if [ -s "$INBOX" ]; then echo DROP_FIRST; else echo SPAWN_FIRST; fi; return 0; }
  STANDUP_DIR="$TMP" mux_boot "x" "cmd" "BR-order"
)"
it "Briefing wird VOR dem Spawn gedroppt (kein Race)"; contains "$ORDER" "DROP_FIRST"

# --- 3) Idempotent: Session läuft schon → kein Spawn, kein Briefing ---
: > "$INBOX"; : > "$SPAWN"
(
  . "$BOOT" 2>/dev/null
  mux_has()   { return 0; }                                   # läuft bereits
  mux_spawn() { printf 'SPAWN|%s\n' "$1" >> "$SPAWN"; return 0; }
  STANDUP_DIR="$TMP" mux_boot "acme_bob" "cmd" "SOLL-NICHT-ERSCHEINEN"
)
it "läuft schon → KEIN mux_spawn";       file_missing "$SPAWN"
it "läuft schon → KEIN Briefing-Drop";   file_missing "$INBOX"

# --- 4) Ohne Briefing: spawnt trotzdem, schreibt aber keine Inbox-Zeile ---
: > "$INBOX"; : > "$SPAWN"
(
  . "$BOOT" 2>/dev/null
  mux_has()   { return 1; }
  mux_spawn() { printf 'SPAWN|%s|%s\n' "$1" "$2" >> "$SPAWN"; return 0; }
  STANDUP_DIR="$TMP" mux_boot "scut" "scut-poll.sh"
)
it "ohne Briefing → spawnt trotzdem";    file_has "$SPAWN" "SPAWN|scut|scut-poll.sh"
it "ohne Briefing → keine Inbox-Zeile";  file_missing "$INBOX"

# --- 5) BOOT_INBOX/BOOT_TO überschreiben Default (STANDUP_DIR/Session) ---
ALT="$TMP/alt_inbox.md"; : > "$ALT"; : > "$INBOX"
(
  . "$BOOT" 2>/dev/null
  mux_has()   { return 1; }
  mux_spawn() { return 0; }
  STANDUP_DIR="$TMP" BOOT_INBOX="$ALT" BOOT_TO="Ada" \
    mux_boot "acme_bob" "cmd" "ziel-override"
)
it "BOOT_INBOX lenkt das Briefing in die alternative Inbox"; file_has "$ALT" "ziel-override"
it "BOOT_TO überschreibt den Adressaten";                    file_has "$ALT" "@Ada"
it "Default-Inbox bleibt bei BOOT_INBOX-Override leer";      file_missing "$INBOX"

# --- 6) Fehlende Session → rc 2 ---
( . "$BOOT" 2>/dev/null; mux_boot "" >/dev/null 2>&1 ); RC=$?
it "fehlende Session → rc 2"; eq "$RC" "2"

# --- 7) Spawn-Fehler propagiert (rc von mux_spawn) ---
: > "$INBOX"
( . "$BOOT" 2>/dev/null; mux_has() { return 1; }; mux_spawn() { return 7; }; \
  STANDUP_DIR="$TMP" mux_boot "y" "cmd" "br" >/dev/null 2>&1 ); RC=$?
it "Spawn-Fehler propagiert (rc!=0)"; neq "$RC" "0"

# --- 8) Keine erreichbare Inbox (weder BOOT_INBOX noch STANDUP_DIR) → NICHT nach /_inbox.md
#        schreiben (Footgun-Guard), aber trotzdem spawnen. ---
: > "$SPAWN"
ROOT_BEFORE="$([ -e /_inbox.md ] && echo exists || echo absent)"
(
  . "$BOOT" 2>/dev/null
  mux_has()   { return 1; }
  mux_spawn() { printf 'SPAWN|%s\n' "$1" >> "$SPAWN"; return 0; }
  unset STANDUP_DIR BOOT_INBOX
  mux_boot "z" "cmd" "br-ohne-inbox" >/dev/null 2>&1
)
it "keine Inbox → spawnt trotzdem";              file_has "$SPAWN" "SPAWN|z"
it "keine Inbox → schreibt NICHT nach /_inbox.md"; eq "$([ -e /_inbox.md ] && echo exists || echo absent)" "$ROOT_BEFORE"

summary
