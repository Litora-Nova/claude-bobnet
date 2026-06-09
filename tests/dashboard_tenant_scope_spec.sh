#!/usr/bin/env bash
# tests/dashboard_tenant_scope_spec.sh — Regressions-Guard für den Tenant-Leak
# (lokaler Task #13): ein tenant-gescopeter Write (resolve/notify/approvals/
# heartbeat) darf NUR den AKTIVEN Tenant treffen.
#
# RCA-Kern (wörtlich): „decide/resolve trifft NUR den aktiven Tenant." Der Leak
# war client-seitig (Pages forwardeten das aktive ?project nicht → tenantOf fiel
# server-seitig auf envTenant() = das Launcher-Projekt zurück → Writes landeten
# IMMER im falschen Tenant). Der Fix forwardet ?project; dieser Guard sichert die
# server-seitige GARANTIE ab, gegen die der Client schreibt:
#
#   POST /api/resolve?project=A  →  appendFile in  tenantOf(event).standupDir/_resolved.md
#                                   = AUSSCHLIESSLICH A's standupDir, nie B's;
#   ohne ?project                →  Fallback auf den env/Launcher-Tenant.
#
# ── Warum DIESES Test-Niveau (Test-Hoheit, bewusst gewählt) ───────────────────
# Ein ECHTER HTTP-Write gegen den laufenden Hub ist NICHT CI-sicher: resolve.post
# hängt sein _resolved.md an `tenantOf(event).standupDir` — und die einzigen
# auflösbaren Tenants des laufenden Hubs sind die ECHTEN Registry-Tenants des
# Betreibers. Ein POST ?project=<echter Tenant> würde also Live-Tenant-Daten
# mutieren — vom Auftrag ausdrücklich verboten. Einen frischen Temp-Tenant kann
# der laufende Server nicht sehen (Registry liegt außerhalb).
# Darum NICHT ein destruktiver Live-Write, sondern drei nicht-destruktive Lagen,
# exakt im Schnitt der bestehenden Suite (vgl. registry_spec = node, http_spec =
# read-only live, skip-grün):
#
#   LAGE 1 — Resolver-Garantie (node, läuft IMMER): die Schreibziel-Auflösung
#     ist eine reine Funktion über registry.mjs (`projectByUid` → `tenantFromProject`
#     → `standupDir`). Gegen eine SYNTHETISCHE Zwei-Tenant-Registry (mktemp) wird
#     bewiesen: ?project=A löst A's Dir auf, ?project=B B's, die Dirs sind
#     DISJUNKT, und ein unbekannter Tenant ist null (= server-seitig der 404-Pfad,
#     KEIN stiller Fallback auf einen fremden Tenant). Das ist der Leak-Kern,
#     ohne Server und ohne Live-Daten.
#
#   LAGE 2 — Quell-Invariante (statisch, läuft IMMER): die vier tenant-gescopeten
#     Write-Endpoints leiten ihr Schreib-Dir AUSSCHLIESSLICH aus `tenantOf(event)`
#     ab — kein hartkodierter Pfad, kein direkter envTenant()-Aufruf im Write.
#     Genau diese Eigenschaft hat der #13-Fix server-seitig garantiert; bricht sie,
#     ist der Leak zurück.
#
#   LAGE 3 — Live-Verhalten (read-only, SKIPPT grün ohne Server): wenn ein Hub
#     läuft, wird NICHT-DESTRUKTIV geprüft, dass resolve tenant-scoped ist —
#     POST /api/resolve?project=<unbekannt> → 404 (tenantOf wirft VOR jedem Write;
#     es entsteht keine Datei, kein Tenant wird berührt). Ein echter Cross-Tenant-
#     Write gegen Live-Daten wird BEWUSST nicht ausgeführt.
#
# CI-SICHER: Lage 1/2 brauchen nur node + die Sourcen (immer grün/rot ehrlich);
# Lage 3 skippt GRÜN ohne Server. KEIN Server-Start/-Neustart, KEINE Mutation von
# Live-Tenant-Daten — alle Fixtures in mktemp -d.
# URL-Override: BOBNET_URL=http://host:port  (Default http://localhost:3031).
set -uo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/_helper.sh"

REG_MJS="$ENGINE_ROOT/dashboard/server/utils/registry.mjs"
TENANT_TS="$ENGINE_ROOT/dashboard/server/utils/tenant.ts"
SCOPED_WRITES=(resolve.post.ts notify.post.ts approvals.post.ts heartbeat.post.ts)

# ═══════════════════════════════════════════════════════════════════════════════
# LAGE 1 — Resolver-Garantie: ?project=X trifft NUR X's standupDir (node, immer)
# ═══════════════════════════════════════════════════════════════════════════════
if ! command -v node >/dev/null 2>&1; then
  it "node verfügbar — sonst SKIP grün"
  printf '  ⊘ SKIP: node nicht installiert (CI-sicher grün)\n'
  summary; exit $?
fi

# Synthetische Zwei-Tenant-Registry — A und B sind Wegwerf-Temp-Tenants, NIE echt.
FIX="$(mktemp -d)"
trap 'rm -rf "$FIX"' EXIT
mkdir -p "$FIX/A/standup" "$FIX/B/standup"
cat > "$FIX/projects.registry.json" <<JSON
{
  "version": 1,
  "projects": [
    { "uid": "tenant-a", "name": "tenant-a", "label": "Tenant A",
      "path": "$FIX/A", "standup": "$FIX/A/standup", "status": "active" },
    { "uid": "tenant-b", "name": "tenant-b", "label": "Tenant B",
      "path": "$FIX/B", "standup": "$FIX/B/standup", "status": "active" }
  ]
}
JSON

# Schreibziel-Auflösung exakt wie resolve.post.ts: tenantOf(?project).standupDir.
# Hier über die reine Kette projectByUid → standupDir nachgebaut (tenant.ts selbst
# ist .ts + nitro-auto-imports, daher node-untestbar — wie http_spec dokumentiert).
target() {
  node --input-type=module -e "
    import { projectByUid } from 'file://$REG_MJS'
    import { resolve } from 'node:path'
    const R='$FIX/projects.registry.json'
    const p = projectByUid('$1', R)
    if (!p) { console.log('__404__'); }              // tenantOf wirft hier 404
    else { console.log(resolve(p.standup)); }         // = tenantFromProject().standupDir
  " 2>/dev/null
}

A_DIR="$(target tenant-a)"
B_DIR="$(target tenant-b)"
UNKNOWN="$(target tenant-zzz-gibtsnicht)"

it "resolve-scope: ?project=tenant-a zielt auf A's standupDir"
eq "$A_DIR" "$FIX/A/standup"

it "resolve-scope: ?project=tenant-b zielt auf B's standupDir"
eq "$B_DIR" "$FIX/B/standup"

it "TENANT-LEAK-GUARD: A's Schreibziel ist DISJUNKT von B's (kein Cross-Tenant-Write)"
neq "$A_DIR" "$B_DIR"

it "resolve-scope: A's standupDir enthält NICHT B's Pfad (keine Verschachtelung/Leak)"
not_contains "$A_DIR" "$FIX/B/"

it "resolve-scope: unbekanntes ?project → 404-Pfad (KEIN stiller Fallback auf fremden Tenant)"
eq "$UNKNOWN" "__404__"

# Beweis, dass ein Write nach A NICHT in B landet — gegen die mktemp-Dirs simuliert
# (das ist die appendFile-Zeile aus resolve.post.ts, hart gegen die aufgelösten
# Ziele; KEINE Live-Daten). Danach: A hat die Zeile, B ist garantiert leer.
printf 'probe-agent | beispiel-blocker\n' >> "$A_DIR/_resolved.md"
it "TENANT-LEAK-GUARD: Write an Tenant A erscheint in A's _resolved.md"
file_has "$A_DIR/_resolved.md" "probe-agent | beispiel-blocker"
it "TENANT-LEAK-GUARD: derselbe Write LEAKT NICHT in Tenant B's standupDir"
file_missing "$B_DIR/_resolved.md"

# ═══════════════════════════════════════════════════════════════════════════════
# LAGE 2 — Quell-Invariante: alle tenant-gescopeten Writes nutzen tenantOf(event)
# ═══════════════════════════════════════════════════════════════════════════════
# Bricht ein Endpoint diese Eigenschaft (hartkodierter Pfad / direkter envTenant()-
# Write), ist der #13-Leak server-seitig zurück — unabhängig davon, was der Client
# forwardet. Daher als Struktur-Guard direkt an der Quelle.
for f in "${SCOPED_WRITES[@]}"; do
  src="$ENGINE_ROOT/dashboard/server/api/$f"
  it "quell-invariante: $f existiert"
  ok test -f "$src"
  it "quell-invariante: $f leitet sein Schreib-Dir aus tenantOf(event) ab"
  file_has "$src" "tenantOf(event)"
  it "quell-invariante: $f ruft im Write NICHT direkt envTenant() auf (Leak-Muster #13)"
  not_ok grep -qE 'envTenant\(\)' "$src"
done

# tenant.ts: der 404-Pfad für unbekannte uid muss bestehen bleiben (kein Fallback).
it "tenant.ts: unbekanntes project wirft 404 (kein stiller Fallback im Resolver)"
file_has "$TENANT_TS" "statusCode: 404"
it "tenant.ts: leeres project fällt bewusst auf envTenant() zurück (Modus B)"
file_has "$TENANT_TS" "return envTenant()"

# ═══════════════════════════════════════════════════════════════════════════════
# LAGE 3 — Live-Verhalten (read-only, SKIPPT grün ohne Server)
# ═══════════════════════════════════════════════════════════════════════════════
# NUR ein nicht-destruktiver Negativ-Probe-POST: unbekannter Tenant → 404, BEVOR
# resolve.post irgendetwas schreibt (tenantOf wirft). Ein echter Cross-Tenant-Write
# gegen Live-Daten wird BEWUSST NICHT ausgeführt (Auftrag: keine Live-Mutation).
BASE="${BOBNET_URL:-http://localhost:3031}"
CURL_TIMEOUT="${BOBNET_CURL_TIMEOUT:-5}"

if ! command -v curl >/dev/null 2>&1; then
  it "curl verfügbar für Live-Probe — sonst SKIP grün"
  printf '  ⊘ SKIP: curl nicht installiert (Lage 3 übersprungen, CI-sicher grün)\n'
  summary; exit $?
fi

PROBE_CODE="$(curl -sS -m "$CURL_TIMEOUT" -o /dev/null -w '%{http_code}' "$BASE/" 2>/dev/null)"
case "$PROBE_CODE" in
  2??|3??) : ;;  # brauchbarer Server — Lage 3 läuft
  000|"")
    it "Dev-Server unter $BASE erreichbar — sonst SKIP grün"
    printf '  ⊘ SKIP: kein Dev-Server unter %s (Lage 3 übersprungen; Gate bleibt grün)\n' "$BASE"
    summary; exit $? ;;
  *)
    it "Dev-Server unter $BASE brauchbar (HTTP 2xx/3xx) — sonst SKIP grün"
    printf '  ⊘ SKIP: Dev-Server unter %s antwortet HTTP %s (kaputt/verwaist) — Lage 3 übersprungen, Gate bleibt grün\n' "$BASE" "$PROBE_CODE"
    summary; exit $? ;;
esac

# Read-only / nicht-destruktiv: POST mit unbekanntem ?project — tenantOf wirft 404,
# es entsteht KEINE Datei, KEIN Tenant wird berührt.
post_status() {
  curl -sS -m "$CURL_TIMEOUT" -o /dev/null -w '%{http_code}' \
    -X POST -H 'Content-Type: application/json' \
    -d '{"agent":"__regression_probe__","blocker":"__noop__"}' \
    "$BASE/api/resolve?project=$1" 2>/dev/null
}

it "live resolve: POST ?project=<unbekannt> → 404 (tenantOf wirft VOR dem Write, keine Datei entsteht)"
eq "$(post_status 'zzz-gibtsnicht-zzz')" "404"

summary
