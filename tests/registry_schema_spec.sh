#!/usr/bin/env bash
# tests/registry_schema_spec.sh — Schema-Conformance-Spec für schemas/registry.schema.json (FR#7).
#
# SPEC-Quelle: schemas/registry.schema.json (draft-07). Prüft, dass das Schema ein BRAUCHBARER
# Vertrag ist, nicht nur dass es existiert:
#   - ein KONFORMER Registry-Eintrag passiert (VALID),
#   - MALFORMED-Varianten werden abgelehnt (INVALID): fehlende uid · bad status-enum ·
#     additionalProperty-Typo · bad uid-pattern · owns-Dupe (uniqueItems) · version-als-String,
#   - das mitgelieferte projects.registry.example.json (falls vorhanden) ist konform.
#
# VALIDATOR-WEG (bewusst, dep-arm — begründet im Header):
#   Die Engine bleibt absichtlich abhängigkeitsarm (CLAUDE.md §5 / dep-arm). Es gibt:
#     • KEIN ajv-Node-Modul (geprüft), und eine neue devDep wäre gegen die dep-arm-Maxime,
#     • KEIN python3 `jsonschema`-Modul (in CI nicht garantiert).
#   → Wir ziehen einen kleinen, self-contained draft-07-SUBSET-Validator inline (pur python3
#     stdlib, kein pip), der GENAU die im Schema benutzten Keywords abdeckt: type
#     (object/array/string/integer — integer != boolean), required, additionalProperties:false,
#     properties, items, $ref(+definitions), enum, pattern, minLength, minimum, uniqueItems.
#   python3 ist ohnehin Voraussetzung von bin/who-owns; fehlt es, skippt die Spec GRÜN.
#   (Wegwerf-Validator-Ansatz auf tests/-Niveau gezogen: inline, ohne Fremd-Dep,
#    gegen mktemp-Fixtures.)
#
# Black-Box: NUR synthetische Fixtures in mktemp -d (acme/engine/tenant-a) — NIE die echte
# projects.registry.json. white-label: keine echten uids/Codenamen/Personas.

set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_helper.sh
. "$HERE/_helper.sh"

SCHEMA="$ENGINE_ROOT/schemas/registry.schema.json"

echo "registry.schema.json — Conformance-Spec (FR#7)"

if [ ! -f "$SCHEMA" ]; then
  it "schemas/registry.schema.json ist vorhanden"
  _fail "fehlt: $SCHEMA"
  summary; exit $?
fi
if ! command -v python3 >/dev/null 2>&1; then
  it "python3 vorhanden (Validator-Voraussetzung) — sonst grüner Skip"
  _pass
  echo "  (python3 fehlt → Schema-Validator nicht lauffähig, Spec übersprungen)"
  summary; exit $?
fi

TMP="$(mktemp -d "${TMPDIR:-/tmp}/registry-schema-spec.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

# ── Inline-Validator (self-contained, stdlib-only) → $TMP/validate.py ──────────────────────
cat > "$TMP/validate.py" <<'PY'
#!/usr/bin/env python3
# Minimaler, self-contained draft-07-SUBSET-Validator (stdlib-only, KEINE ajv/jsonschema-Dep).
# Deckt GENAU die in registry.schema.json benutzten Keywords ab.
import json, re, sys

def deref(node, root):
    if isinstance(node, dict) and "$ref" in node:
        ref = node["$ref"]
        assert ref.startswith("#/"), f"nur lokale $ref unterstuetzt: {ref}"
        cur = root
        for part in ref[2:].split("/"):
            cur = cur[part]
        return cur
    return node

JTYPE = {"object": dict, "array": list, "string": str, "integer": int,
         "number": (int, float), "boolean": bool}

def validate(inst, schema, root, path, errs):
    schema = deref(schema, root)
    t = schema.get("type")
    if t:
        # bool ist in Python int-Subtyp; integer/number duerfen KEIN bool sein
        if t in ("integer", "number") and isinstance(inst, bool):
            errs.append(f"{path}: erwartet {t}, bekam boolean"); return
        if not isinstance(inst, JTYPE[t]):
            errs.append(f"{path}: erwartet {t}, bekam {type(inst).__name__}"); return
    if "enum" in schema and inst not in schema["enum"]:
        errs.append(f"{path}: '{inst}' nicht in enum {schema['enum']}")
    if "pattern" in schema and isinstance(inst, str):
        if not re.search(schema["pattern"], inst):
            errs.append(f"{path}: '{inst}' verletzt pattern {schema['pattern']}")
    if "minLength" in schema and isinstance(inst, str) and len(inst) < schema["minLength"]:
        errs.append(f"{path}: kuerzer als minLength {schema['minLength']}")
    if "minimum" in schema and isinstance(inst, (int, float)) and not isinstance(inst, bool):
        if inst < schema["minimum"]:
            errs.append(f"{path}: < minimum {schema['minimum']}")
    if isinstance(inst, dict):
        props = schema.get("properties", {})
        for req in schema.get("required", []):
            if req not in inst:
                errs.append(f"{path}: Pflichtfeld '{req}' fehlt")
        if schema.get("additionalProperties") is False:
            for k in inst:
                if k not in props:
                    errs.append(f"{path}: unbekanntes Feld '{k}' (additionalProperties:false)")
        for k, v in inst.items():
            if k in props:
                validate(v, props[k], root, f"{path}.{k}", errs)
    if isinstance(inst, list):
        items = schema.get("items")
        if items:
            for i, el in enumerate(inst):
                validate(el, items, root, f"{path}[{i}]", errs)
        if schema.get("uniqueItems"):
            seen = []
            for el in inst:
                if el in seen:
                    errs.append(f"{path}: doppeltes Element {el!r} (uniqueItems)")
                else:
                    seen.append(el)

def main():
    schema = json.load(open(sys.argv[1]))
    data = json.load(open(sys.argv[2]))
    errs = []
    validate(data, schema, schema, "$", errs)
    if errs:
        print("INVALID")
        for e in errs:
            print("  -", e)
        sys.exit(1)
    print("VALID")
    sys.exit(0)

main()
PY

# valid_against <fixture> : 0 wenn der Validator das Fixture als VALID akzeptiert.
valid_against() { python3 "$TMP/validate.py" "$SCHEMA" "$1" >/dev/null 2>&1; }

# ── 0) Selbst-Vertrauen: erst beweisen, dass der Validator beide Richtungen kann ──────────
#   (sonst koennte ein „immer-VALID"-Validator die Reject-Tests tautologisch gruen faerben).
it "Validator-Sanity: akzeptiert ein triviales VALID-Doc UND lehnt ein triviales INVALID ab"
cat > "$TMP/_sanity_ok.json" <<'JSON'
{ "version": 0, "projects": [] }
JSON
cat > "$TMP/_sanity_bad.json" <<'JSON'
{ "projects": [] }
JSON
if valid_against "$TMP/_sanity_ok.json" && ! valid_against "$TMP/_sanity_bad.json"; then _pass
else _fail "Validator diskriminiert nicht (akzeptiert/ablehnt nicht wie erwartet)"; fi

# ── 1) KONFORMER Eintrag (alle Pflicht- + viele optionale Felder) → VALID ─────────────────
it "konformer Registry-Eintrag (uid/name/path/standup + optional) → VALID"
cat > "$TMP/conform.json" <<'JSON'
{ "version": 1, "_note": "synthetisches Fixture",
  "projects": [
    { "uid": "acme", "name": "acme-app", "label": "Acme App", "path": "/srv/acme",
      "standup": "/srv/acme/standup", "theme": "minimal", "status": "active",
      "responsibility": "Produkt + Deployment",
      "owns": ["acme-app/backend", "acme-app/frontend"] },
    { "uid": "engine", "name": "engine-core", "path": "/srv/engine",
      "standup": "/srv/engine/standup", "status": "paused", "parent": "acme",
      "owns": ["engine/scripts"] },
    { "uid": "tenant-a", "name": "tenant-a-svc", "path": "/srv/tenant-a",
      "standup": "/srv/tenant-a/standup", "status": "archived" }
  ] }
JSON
ok valid_against "$TMP/conform.json"

# ── 2) MALFORMED: fehlende uid (Pflichtfeld) → INVALID ────────────────────────────────────
it "malformed: fehlende uid → abgelehnt"
cat > "$TMP/no_uid.json" <<'JSON'
{ "version": 1, "projects": [ { "name": "acme-app", "path": "/srv/acme", "standup": "/srv/acme/standup" } ] }
JSON
not_ok valid_against "$TMP/no_uid.json"

# ── 3) MALFORMED: bad status-enum ─────────────────────────────────────────────────────────
it "malformed: status 'running' (nicht im enum active/paused/archived) → abgelehnt"
cat > "$TMP/bad_status.json" <<'JSON'
{ "version": 1, "projects": [ { "uid": "acme", "name": "acme-app", "path": "/srv/acme", "standup": "/srv/acme/standup", "status": "running" } ] }
JSON
not_ok valid_against "$TMP/bad_status.json"

# ── 4) MALFORMED: additionalProperty-Typo (additionalProperties:false greift) ─────────────
it "malformed: Feld-Typo 'responsability' (additionalProperties:false) → abgelehnt"
cat > "$TMP/extra_prop.json" <<'JSON'
{ "version": 1, "projects": [ { "uid": "acme", "name": "acme-app", "path": "/srv/acme", "standup": "/srv/acme/standup", "responsability": "typo" } ] }
JSON
not_ok valid_against "$TMP/extra_prop.json"

# ── 5) MALFORMED: bad uid-pattern (Großbuchstabe/Underscore verletzt ^[a-z0-9][a-z0-9-]*$) ─
it "malformed: uid 'Acme_X' verletzt das uid-pattern → abgelehnt"
cat > "$TMP/bad_uid.json" <<'JSON'
{ "version": 1, "projects": [ { "uid": "Acme_X", "name": "acme-app", "path": "/srv/acme", "standup": "/srv/acme/standup" } ] }
JSON
not_ok valid_against "$TMP/bad_uid.json"

# ── 6) MALFORMED: owns-Dupe (uniqueItems) ─────────────────────────────────────────────────
it "malformed: doppelter owns-Eintrag (uniqueItems) → abgelehnt"
cat > "$TMP/owns_dupe.json" <<'JSON'
{ "version": 1, "projects": [ { "uid": "acme", "name": "acme-app", "path": "/srv/acme", "standup": "/srv/acme/standup", "owns": ["acme-app/backend", "acme-app/backend"] } ] }
JSON
not_ok valid_against "$TMP/owns_dupe.json"

# ── 7) MALFORMED: version als String statt integer ────────────────────────────────────────
it "malformed: version \"1\" (String statt integer) → abgelehnt"
cat > "$TMP/ver_str.json" <<'JSON'
{ "version": "1", "projects": [ { "uid": "acme", "name": "acme-app", "path": "/srv/acme", "standup": "/srv/acme/standup" } ] }
JSON
not_ok valid_against "$TMP/ver_str.json"

# ── 8) Passt das Schema zur mitgelieferten projects.registry.example.json? ────────────────
#   Auflösung wie bin/who-owns: TOOLHUB = ENGINE_ROOT/.. . Sucht im Engine-Root, im
#   Tool-Hub-Root und (worktree-robust, white-label) am echten Repo-Root via git-common-dir
#   + dessen Parent. Fehlt die Datei (reines public-Repo-Checkout) → grüner Skip.
TOOLHUB="$(cd "$ENGINE_ROOT/.." && pwd)"
REPO_ROOT=""; REPO_PARENT=""
if _common="$(git -C "$ENGINE_ROOT" rev-parse --git-common-dir 2>/dev/null)"; then
  REPO_ROOT="$(cd "$(dirname "$_common")" 2>/dev/null && pwd)" || REPO_ROOT=""
  [ -n "$REPO_ROOT" ] && REPO_PARENT="$(cd "$REPO_ROOT/.." 2>/dev/null && pwd)" || REPO_PARENT=""
fi
EXAMPLE=""
for cand in \
  "$ENGINE_ROOT/projects.registry.example.json" \
  "$TOOLHUB/projects.registry.example.json" \
  "${REPO_ROOT:+$REPO_ROOT/projects.registry.example.json}" \
  "${REPO_PARENT:+$REPO_PARENT/projects.registry.example.json}"; do
  [ -n "$cand" ] && [ -f "$cand" ] && { EXAMPLE="$cand"; break; }
done
if [ -n "$EXAMPLE" ]; then
  it "mitgeliefertes projects.registry.example.json ($EXAMPLE) ist schema-konform"
  ok valid_against "$EXAMPLE"
else
  it "projects.registry.example.json nicht gefunden (public-Checkout) → grüner Skip"
  _pass
fi

summary
