#!/usr/bin/env bash
# channels/email.sh — SCUT-Channel-Adapter: Email → normalisiertes Event (STUB).
#
# Soll: ein IMAP-Postfach (oder einen maildir/Webhook) abfragen und pro neuer Mail EINE normalisierte
# Event-Zeile auf stdout emittieren (TSV, 6 Felder — siehe scut-router.sh). Pipe in den Router:
#
#     scripts/channels/email.sh | scripts/scut-router.sh
#
# Target-Konvention (Vorschlag): aus dem Subject ein führendes "[<uid>]" / "@<Agent>" lesen
#   (z.B. Subject "[acme]@Bill: Key rotieren"), sonst aus einer Plus-Adresse
#   (team+acme-bill@litora-nova.com → [acme]@Bill). Kein Treffer → ungerichtet → Review-Queue.
#
# TODO (Phase D+): IMAP-Anbindung (Secrets in SCUT_SECRETS_DIR/email_*), Dedup via Message-ID-Offset.
#
# --demo : gibt zwei Beispiel-Events im normalisierten Format aus (für den Router-Smoke-Test).
set -uo pipefail
if [ "${1:-}" = "--demo" ]; then
  now="$(date +%s)"
  printf 'email\t<msgid-1@x>\t%s\textern\t[acme]@Bill\tBitte den Vertrag gegenlesen\n' "$now"
  printf 'email\t<msgid-2@x>\t%s\tkunde\t\tAllgemeine Anfrage ohne Adressaten\n' "$now"
  exit 0
fi
echo "email-channel: STUB — noch nicht angebunden. '--demo' zeigt das normalisierte Format." >&2
exit 0
