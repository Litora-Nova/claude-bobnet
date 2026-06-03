#!/usr/bin/env bash
# channels/github.sh — SCUT-Channel-Adapter: GitHub → normalisiertes Event (STUB).
#
# Soll: GitHub-Notifications/Issue-/PR-Kommentare via `gh api` (oder Webhook) abfragen und pro
# Ereignis EINE normalisierte Event-Zeile auf stdout emittieren (TSV, 6 Felder — siehe scut-router.sh):
#
#     scripts/channels/github.sh | scripts/scut-router.sh
#
# Target-Konvention (Vorschlag): das Repo → Registry-uid mappen (z.B. via team.config repo→uid),
#   ein "@<Agent>" aus dem Kommentartext lesen. Kein Mapping → ungerichtet → Review-Queue.
#
# TODO (Phase D+): `gh api notifications` pollen, Repo→uid-Tabelle (team.config), since-Cursor als Offset.
#
# --demo : gibt zwei Beispiel-Events im normalisierten Format aus (für den Router-Smoke-Test).
set -uo pipefail
if [ "${1:-}" = "--demo" ]; then
  now="$(date +%s)"
  printf 'github\tcomment-1\t%s\tgithub:octocat\t[acme]@Riker\tPR #42 braucht Review\n' "$now"
  printf 'github\tcomment-2\t%s\tgithub:extern\t\tIssue ohne klaren Adressaten\n' "$now"
  exit 0
fi
echo "github-channel: STUB — noch nicht angebunden. '--demo' zeigt das normalisierte Format." >&2
exit 0
