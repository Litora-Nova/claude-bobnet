#!/usr/bin/env bash
# tests/who_owns_spec.sh — Behavior-Spec für bin/who-owns (FR#7, Wave 2).
#
# SPEC-Quelle: bin/who-owns-Header + schemas/registry.schema.json (`owns`, `responsibility`).
#   who-owns <query>  beantwortet „who owns <X>?" gegen die Registry und matcht in dieser
#   Prioritätsreihenfolge:
#     1) owns[]-Pfad-Match  (query == owns | query unter owns | owns unter query) —
#        spezifischster (längster) owns-Pfad gewinnt; Reason-String nennt den Treffer-Pfad.
#     2) project-`path`-Match  (query == path | query unter path).
#     3) Stichwort (substring, case-insensitiv) in responsibility / owns / name / label / uid.
#   Exit: 0 = Treffer (oder --list) · 1 = kein Treffer (klare Meldung) · 2 = Registry fehlt.
#   Registry-Auflösung override: BOBNET_REGISTRY=<datei>.
#
# Black-Box: NICHT den eingebauten --self-test aufrufen (self-confirming, zählt laut
# tests/README NICHT als Gate). Statt dessen Wegwerf-Fixture-Registries in mktemp -d und
# der Output/Exit von `BOBNET_REGISTRY=<fixture> bin/who-owns <query>` asserten.
#
# white-label: nur synthetische uids (acme/engine/tenant-a), keine echten Codenamen/Personas.

set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_helper.sh
. "$HERE/_helper.sh"

WHO_OWNS="$ENGINE_ROOT/bin/who-owns"

echo "who-owns — Behavior-Spec (FR#7)"

if [ ! -x "$WHO_OWNS" ]; then
  it "bin/who-owns ist vorhanden + ausführbar"
  _fail "fehlt oder nicht ausführbar: $WHO_OWNS"
  summary; exit $?
fi
if ! command -v python3 >/dev/null 2>&1; then
  it "python3 vorhanden (who-owns-Voraussetzung) — sonst grüner Skip"
  _pass
  echo "  (python3 fehlt → who-owns nicht lauffähig, Spec übersprungen)"
  summary; exit $?
fi

TMP="$(mktemp -d "${TMPDIR:-/tmp}/who-owns-spec.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

REG="$TMP/registry.json"
cat > "$REG" <<'JSON'
{ "version": 1, "projects": [
  { "uid": "acme", "name": "acme-app", "label": "Acme App", "path": "/srv/acme",
    "standup": "/srv/acme/standup", "responsibility": "Produkt + Deployment-Pipeline",
    "owns": ["acme-app/backend", "acme-app/backend/api", "acme-app/frontend"] },
  { "uid": "engine", "name": "engine-core", "label": "Engine", "path": "/srv/engine",
    "standup": "/srv/engine/standup", "responsibility": "Shared CI + Release",
    "owns": ["engine/scripts", "engine/dashboard"] },
  { "uid": "tenant-a", "name": "tenant-a-svc", "label": "Tenant A", "path": "/srv/tenant-a",
    "standup": "/srv/tenant-a/standup", "responsibility": "Billing-Flows",
    "owns": ["tenant-a-svc/worker"] }
] }
JSON

# who <query…> → setzt $OUT (stdout+stderr gemischt) und $RC (exit code).
who() {
  OUT="$(BOBNET_REGISTRY="$REG" bash "$WHO_OWNS" "$@" 2>&1)"; RC=$?
}

# ── 1) owns[]-Pfad-Match: exakt ───────────────────────────────────────────────────────────
it "owns-Pfad exakt: 'engine/scripts' → engine, Reason nennt genau diesen owns-Pfad"
who "engine/scripts"
eq "$RC" 0
contains "$OUT" "engine"
contains "$OUT" "owns 'engine/scripts'"

# ── 2) owns[]-Pfad-Match: Unterpfad (query liegt UNTER einem owns-Eintrag) ─────────────────
it "owns-Unterpfad: 'engine/dashboard/server/api' → engine via owns 'engine/dashboard'"
who "engine/dashboard/server/api"
eq "$RC" 0
contains "$OUT" "engine"
contains "$OUT" "owns 'engine/dashboard'"

# ── 3) Spezifischster owns gewinnt (NICHT-tautologisch: der TIEFERE Pfad muss genannt sein,
#       der flachere darf NICHT als Reason gewinnen) ────────────────────────────────────────
it "spezifischster owns gewinnt: 'acme-app/backend/api/v2' → via owns 'acme-app/backend/api'"
who "acme-app/backend/api/v2"
eq "$RC" 0
contains "$OUT" "acme"
contains "$OUT" "owns 'acme-app/backend/api'"
it "… und NICHT über den flacheren owns 'acme-app/backend' (sonst wäre das Matching unscharf)"
not_contains "$OUT" "via owns 'acme-app/backend']"

# ── 4) project-`path`-Match (query == path-Root oder darunter) ────────────────────────────
it "path-Match: '/srv/tenant-a/some/sub' → tenant-a via path (kein owns trifft)"
who "/srv/tenant-a/some/sub"
eq "$RC" 0
contains "$OUT" "tenant-a"
contains "$OUT" "path '/srv/tenant-a'"

# ── 5) keyword: responsibility (Prosa-Stichwort) ──────────────────────────────────────────
it "keyword in responsibility: 'Billing' → tenant-a via keyword"
who "Billing"
eq "$RC" 0
contains "$OUT" "tenant-a"
contains "$OUT" "keyword"

# ── 5b) keyword: name ─────────────────────────────────────────────────────────────────────
it "keyword in name: 'engine-core' → engine via keyword"
who "engine-core"
eq "$RC" 0
contains "$OUT" "engine"
contains "$OUT" "keyword"

# ── 5c) keyword: uid (case-insensitiv) ────────────────────────────────────────────────────
it "keyword in uid (case-insensitiv): 'TENANT-A' → tenant-a"
who "TENANT-A"
eq "$RC" 0
contains "$OUT" "tenant-a"

# ── 6) kein Treffer → exit 1 + klare Meldung ──────────────────────────────────────────────
it "kein Treffer: 'voellig-fremd-xyz' → exit 1"
who "voellig-fremd-xyz"
eq "$RC" 1
it "… mit klarer 'kein Treffer'-Meldung"
contains "$OUT" "kein Treffer"

# ── 7) --list zeigt ALLE Projekte ─────────────────────────────────────────────────────────
it "--list listet jedes registrierte Projekt (uid) auf, exit 0"
who --list
eq "$RC" 0
contains "$OUT" "acme"
contains "$OUT" "engine"
contains "$OUT" "tenant-a"

# ── 8) fehlende Registry → exit 2 ─────────────────────────────────────────────────────────
it "fehlende Registry → exit 2"
OUT="$(BOBNET_REGISTRY="$TMP/does-not-exist.json" bash "$WHO_OWNS" "x" 2>&1)"; RC=$?
eq "$RC" 2

# ── 9) NICHT-TAUTOLOGIE-GUARD: der Matcher diskriminiert wirklich ──────────────────────────
#   Beweist, dass nicht jeder Query alles trifft. 'engine/scripts' darf NICHT 'tenant-a'
#   liefern; 'Billing' darf NUR tenant-a treffen. (Gegenprobe lokal verifiziert: eine
#   bewusst falsche Erwartung — z. B. who "engine/scripts" → contains tenant-a — wird ROT.)
it "Diskriminierungs-Guard: owns-Query 'engine/scripts' trifft NICHT den fremden tenant-a"
who "engine/scripts"
not_contains "$OUT" "tenant-a"

it "Diskriminierungs-Guard: keyword 'Billing' trifft NICHT acme/engine (nur tenant-a)"
who "Billing"
not_contains "$OUT" "acme"
not_contains "$OUT" "engine"

summary
