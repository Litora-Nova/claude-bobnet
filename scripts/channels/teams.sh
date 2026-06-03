#!/usr/bin/env bash
# channels/teams.sh — SCUT-Channel-Adapter: MS Teams → normalisiertes Event (STUB).
#
# Soll: einen Teams-Incoming-Webhook / Graph-API-Channel abfragen und pro Nachricht EINE
# normalisierte Event-Zeile auf stdout emittieren (TSV, 6 Felder — siehe scut-router.sh):
#
#     scripts/channels/teams.sh | scripts/scut-router.sh
#
# Target-Konvention (Vorschlag): Teams-Channel → Registry-uid mappen (team.config), "@<Agent>"
#   aus dem Mention/Text lesen. Kein Mapping → ungerichtet → Review-Queue.
#
# TODO (Phase D+): Graph-API / Bot-Framework-Anbindung (Secrets in SCUT_SECRETS_DIR/teams_*).
#
# --demo : gibt ein Beispiel-Event im normalisierten Format aus (für den Router-Smoke-Test).
set -uo pipefail
if [ "${1:-}" = "--demo" ]; then
  now="$(date +%s)"
  printf 'teams\tmsg-1\t%s\tchef\t@Bob\tStatus zum Sprint bitte\n' "$now"
  exit 0
fi
echo "teams-channel: STUB — noch nicht angebunden. '--demo' zeigt das normalisierte Format." >&2
exit 0
