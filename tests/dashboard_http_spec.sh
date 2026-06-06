#!/usr/bin/env bash
# tests/dashboard_http_spec.sh — Black-Box-Spec gegen den LAUFENDEN Dev-Server
# (Default :3031, der den Env-Tenant „Engine-standup" fährt). Prüft die Teile der
# Multi-Tenant-Schicht (#9/#10), die NUR im echten Nuxt/H3-Kontext beobachtbar sind
# und sich daher NICHT als nackte node-Unit testen lassen:
#   • GET /manifest.webmanifest  → dynamisches PWA-Manifest (Cookie→Titel-Route):
#       Content-Type application/manifest+json, Cache-Control private (tenant-abh.),
#       JSON mit name/short_name (ohne Cookie: Env-Tenant / Hub-Branding).
#   • GET /api/projects          → tenant-NEUTRALE Flotte: {projects:[…], updatedAt}
#       je Eintrag uid/activity (registered|running|working|idle|blocked) — der
#       Rollup aus activity.mjs + tenantFromProject + teamOf im Zusammenspiel.
#   • GET /api/standup?project=<unbekannt> → 404 (tenant.ts: kein stiller Fallback
#       auf ein fremdes Team; der createError-404-Pfad, der als Unit createError braucht).
#
# NUR-LESEND: ausschließlich GETs, kein Start/Stop/Reload des Servers, keine Writes.
# CI-SICHER: läuft KEIN Server auf der Probe-URL, SKIPPT die Spec GRÜN (mit Hinweis)
#   — das Gate darf ohne Dev-Server NICHT rot werden.
# URL-Override: BOBNET_URL=http://host:port  (Default http://localhost:3031).
set -uo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/_helper.sh"

BASE="${BOBNET_URL:-http://localhost:3031}"
CURL_TIMEOUT="${BOBNET_CURL_TIMEOUT:-5}"

# --- Voraussetzungen / sauberer Skip -----------------------------------------
if ! command -v curl >/dev/null 2>&1; then
  it "curl verfügbar — sonst SKIP grün"
  printf '  ⊘ SKIP: curl nicht installiert (CI-sicher grün)\n'
  summary; exit $?
fi
# Server-Liveness-Probe: erreichbar, wenn die Wurzel einen HTTP-Status liefert.
if ! curl -sS -m "$CURL_TIMEOUT" -o /dev/null "$BASE/" 2>/dev/null; then
  it "Dev-Server unter $BASE erreichbar — sonst SKIP grün"
  printf '  ⊘ SKIP: kein Dev-Server unter %s (Gate bleibt grün; nur-lesende Live-Spec)\n' "$BASE"
  summary; exit $?
fi

# Helfer (nur lesende GETs)
body()   { curl -sS -m "$CURL_TIMEOUT" "$BASE$1" 2>/dev/null; }
headers(){ curl -sS -m "$CURL_TIMEOUT" -D - -o /dev/null "$BASE$1" 2>/dev/null; }
status() { curl -sS -m "$CURL_TIMEOUT" -o /dev/null -w '%{http_code}' "$BASE$1" 2>/dev/null; }

# ── /manifest.webmanifest — dynamisches Manifest ──────────────────────────────
MAN_H="$(headers /manifest.webmanifest)"
MAN_B="$(body /manifest.webmanifest)"

it "manifest: Content-Type application/manifest+json (dynamische Route, nicht statisch)"
contains "$(printf '%s' "$MAN_H" | tr 'A-Z' 'a-z')" "application/manifest+json"

it "manifest: Cache-Control private (tenant-abhängig, nicht nutzerübergreifend teilbar)"
contains "$(printf '%s' "$MAN_H" | tr 'A-Z' 'a-z')" "cache-control: private"

it "manifest: JSON trägt einen name (ohne Cookie: Env-Tenant/Hub-Branding)"
contains "$MAN_B" '"name"'

it "manifest: JSON trägt short_name"
contains "$MAN_B" '"short_name"'

it "manifest: display standalone (PWA-Kern unverändert)"
contains "$MAN_B" '"display": "standalone"'

# ── /api/projects — tenant-neutrale Flotte ────────────────────────────────────
PROJ_B="$(body /api/projects)"

it "api/projects: liefert eine projects-Liste"
contains "$PROJ_B" '"projects"'

it "api/projects: trägt updatedAt (Frische-Stempel des Rollups)"
contains "$PROJ_B" '"updatedAt"'

it "api/projects: trägt das probe-Flag (tmux-Probe an/aus, #10)"
contains "$PROJ_B" '"probe"'

it "api/projects: Einträge tragen einen activity-Status (registered|running|working|idle|blocked)"
# Mindestens einer der dokumentierten Aktivitäts-Werte muss auftauchen.
ACT="$(printf '%s' "$PROJ_B" | grep -oE '"activity":[ ]*"(registered|running|working|idle|blocked)"' | head -1)"
neq "$ACT" ""

it "api/projects: kein roher Server-Crash (kein 500-Statuscode)"
neq "$(status /api/projects)" "500"

# ── 404-Semantik (tenant.ts) — unbekannte uid → kein stiller Fallback ─────────
it "tenant 404: unbekanntes ?project=<uid> → HTTP 404 (kein Fallback auf fremdes Team)"
eq "$(status '/api/standup?project=zzz-gibtsnicht-zzz')" "404"

it "tenant 404: auch /api/heartbeats?project=<unbekannt> → 404 (tenant-weit konsistent)"
eq "$(status '/api/heartbeats?project=zzz-gibtsnicht-zzz')" "404"

summary
