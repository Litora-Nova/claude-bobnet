#!/usr/bin/env bash
# Health-Watch (cron): prüft Staging-Host (HTTPS 200 + SSL-Restlaufzeit) + BobNet.
# Env: STANDUP_DIR, HEALTH_HOST (Staging-Domain), BOBNET_URL (Default localhost:3030).
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; ROOT="$(cd "$DIR/../.." && pwd)"; ST="${STANDUP_DIR:-$ROOT/standup}"
H="${HEALTH_HOST:-staging.example.com}"; BN_URL="${BOBNET_URL:-http://localhost:3030}"; fail=""
sc="$(curl -s -o /dev/null -w '%{http_code}' --max-time 12 "https://$H" 2>/dev/null)"; [ "$sc" = "200" ] || fail="$fail Staging=$sc"
bn="$(curl -s -o /dev/null -w '%{http_code}' --max-time 8 "$BN_URL" 2>/dev/null)"; [ "$bn" = "200" ] || fail="$fail BobNet=$bn"
end="$(echo | timeout 12 openssl s_client -servername "$H" -connect "$H:443" 2>/dev/null | openssl x509 -noout -enddate 2>/dev/null | sed 's/notAfter=//')"
if [ -n "$end" ]; then es="$(date -d "$end" +%s 2>/dev/null)"; now="$(date +%s)"; [ -n "$es" ] && { dleft=$(( (es-now)/86400 )); [ "$dleft" -lt 14 ] && fail="$fail SSL=${dleft}d"; }; fi
if [ -n "$fail" ]; then "$ST/scut.sh" "Health-Watch AUSFALL:$fail" urgent >/dev/null 2>&1; echo "[health] FAIL$fail"; else echo "[health] ok (staging=$sc bobnet=$bn)"; fi
