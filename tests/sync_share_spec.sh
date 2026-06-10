#!/usr/bin/env bash
# tests/sync_share_spec.sh — Black-Box-Spec für bin/sync-share.
#
# Spec-Quelle: team-rules/comms.md §6 (Bobiverse-Sync, Whitelist-only) + Header von
# bin/sync-share + team-rules/sync-share.items:
#   - erzeugt .stignore-Whitelist: Negationen für die Items, Catch-all '*' als LETZTE Zeile
#   - legt fehlende Items an (Ordner bzw. leere Datei), überschreibt nichts
#   - Projekt-Override _dev_team/team-rules/sync-share.items ersetzt die Engine-Liste
#   - Sicherheits-Bremsen: verweigert /, $HOME und Secret-Pfade in der Whitelist
#   - idempotent; --no-register (Default) fasst keine Sync-Dienst-Config an
. "$(dirname "${BASH_SOURCE[0]}")/_helper.sh"

SYNC_SHARE="$ENGINE_ROOT/bin/sync-share"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "sync_share_spec:"

# --- Happy path: Default-Whitelist auf frischer Projekt-Wurzel ---
PROJ="$TMP/acme"
mkdir -p "$PROJ"
OUT="$(bash "$SYNC_SHARE" "$PROJ" --label acme --no-register 2>&1)"
RC=$?
it "läuft auf frischer Wurzel durch (Exit 0)";   eq "$RC" "0"
it "legt .stignore an";                          ok test -s "$PROJ/.stignore"
it "legt _inbox.md an (leer ok)";                ok test -e "$PROJ/_inbox.md"
it "legt _inbox/ an";                            ok test -d "$PROJ/_inbox"
it "legt plan/ an";                              ok test -d "$PROJ/plan"
it "legt share/ an";                             ok test -d "$PROJ/share"

it "Whitelist: Negation für _inbox.md";          file_has "$PROJ/.stignore" '!/_inbox.md'
it "Whitelist: Negation für plan-Inhalte";       file_has "$PROJ/.stignore" '!/plan/**'
it "Whitelist: Negation für share-Inhalte";      file_has "$PROJ/.stignore" '!/share/**'
it "Whitelist: Warn-Header vorhanden";           file_has "$PROJ/.stignore" 'NICHT LÖSCHEN'
LAST="$(grep -v '^$' "$PROJ/.stignore" | tail -1)"
it "Catch-all '*' ist die LETZTE Zeile";         eq "$LAST" "*"
FIRST_MATCH="$(grep -nE '^\*$' "$PROJ/.stignore" | head -1 | cut -d: -f1)"
NEG_AFTER="$(awk -v n="$FIRST_MATCH" 'NR>n && /^!/' "$PROJ/.stignore")"
it "keine Negation NACH dem Catch-all";          eq "$NEG_AFTER" ""

# --- Nichts überschreiben + idempotent ---
echo "wichtig" > "$PROJ/_inbox.md"
bash "$SYNC_SHARE" "$PROJ" --label acme --no-register >/dev/null 2>&1
it "überschreibt vorhandene _inbox.md NICHT";    file_has "$PROJ/_inbox.md" "wichtig"
SUM1="$(cksum "$PROJ/.stignore")"
bash "$SYNC_SHARE" "$PROJ" --label acme --no-register >/dev/null 2>&1
SUM2="$(cksum "$PROJ/.stignore")"
it "idempotent: .stignore deterministisch";      eq "$SUM1" "$SUM2"

# --- Projekt-Override ersetzt die Engine-Liste ---
mkdir -p "$PROJ/_dev_team/team-rules"
printf '_inbox.md\ndocs\n' > "$PROJ/_dev_team/team-rules/sync-share.items"
bash "$SYNC_SHARE" "$PROJ" --label acme --no-register >/dev/null 2>&1
it "Override: docs/ wird angelegt";              ok test -d "$PROJ/docs"
it "Override: docs in Whitelist";                file_has "$PROJ/.stignore" '!/docs'
OUT="$(grep -c '!/plan' "$PROJ/.stignore" || true)"
it "Override ERSETZT Engine-Liste (kein plan)";  eq "$OUT" "0"

# --- Sicherheits-Bremsen ---
it "verweigert \$HOME als Share-Wurzel"
not_ok bash "$SYNC_SHARE" "$HOME" --label home --no-register
printf '.secrets\n' > "$PROJ/_dev_team/team-rules/sync-share.items"
OUT="$(bash "$SYNC_SHARE" "$PROJ" --label acme --no-register 2>&1)"
RC=$?
it "verweigert Secret-Pfad in der Whitelist";    neq "$RC" "0"
it "Fehlermeldung nennt den Secret-Refuse";      contains "$OUT" "REFUSED"

# --- Pflicht-Args ---
mkdir -p "$TMP/p2"
bash "$SYNC_SHARE" "$TMP/p2" --no-register >/dev/null 2>&1
RC=$?
it "ohne --label → Fehler";                      neq "$RC" "0"

summary
