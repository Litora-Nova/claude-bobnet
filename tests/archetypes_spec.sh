#!/usr/bin/env bash
# tests/archetypes_spec.sh — Struktur-/Schema-Spec für archetypes/*.json (Phase C: model+tags).
#
# SPEC-Quelle: schemas/archetype.schema.json (Kanon) + archetypes/README.md §"Phase C" +
#              Bob-Auftrag 2026-06-02 (Bill erweiterte das Schema um `model`+`tags`, 20 Archetypen
#              angefasst → neue Struktur-Pfade brauchen eine Spec, TDD-Disziplin).
#
# Black-Box, READ-ONLY: liest die ECHTEN archetypes/*.json + team-rules/tags/*.md im Engine-Tree.
# Schreibt NICHTS ins Repo (kein mktemp-Fixture nötig — die zu prüfenden Files SIND das SUT).
# JSON-Parsing via python3 (wie die anderen Specs python nutzen) — kein jq-Zwang.
#
# Geprüfte Invarianten (Behavior > Source-Pattern: wir parsen + asserten Werte, greppen nicht):
#   1. Jeder archetypes/*.json ist valides JSON.
#   2. Schema-Konformität der NEUEN Felder:
#        - `model` (falls vorhanden) ∈ {opus, sonnet, haiku}.
#        - `tags`  (falls vorhanden) = Array von Slug-Strings (^[a-z0-9][a-z0-9-]*$).
#   3. Vollständigkeit: jeder Archetyp AUSSER coworker/human hat `model` UND `tags`
#        (`tags` darf leer sein, z.B. roamer/sonde — Feld muss aber DA sein).
#        coworker/human dürfen `model` UND `tags` BEIDE fehlen (extern/Mensch, keine gespawnte Instanz).
#   4. `gateTier` weiterhin vorhanden (Phase-A-Regression-Schutz) — bei allen außer coworker/human.
#        (Begründung: coworker.json/human.json tragen schon im master-Stand KEIN gateTier und das
#         Schema listet gateTier NICHT als required → "in JEDEM Archetyp" wäre rot gegen master.
#         Wir spiegeln die echte, konsistente Regel: gateTier-Pflicht deckungsgleich mit model/tags-Pflicht.
#         Siehe Heartbeat/Handoff an Bob.)
#   5. Tag-Integrität: jeder in irgendeinem Archetyp gelistete Tag hat eine team-rules/tags/<tag>.md
#        (keine toten Tags).

set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_helper.sh
. "$HERE/_helper.sh"

ARCH_DIR="$ENGINE_ROOT/archetypes"
TAGS_DIR="$ENGINE_ROOT/team-rules/tags"
PY="${PYTHON:-python3}"

echo "archetypes/*.json — Struktur-/Schema-Spec (Phase C: model+tags)"

# Archetypen, die per Definition KEIN model/tags/gateTier haben (extern/Mensch):
EXEMPT_RE='^(coworker|human)$'
MODELS_VALID="opus sonnet haiku"
TAG_SLUG_RE='^[a-z0-9][a-z0-9-]*$'

# ── Vorbedingungen ──────────────────────────────────────────────────────────────────────────
it "Vorbedingung: archetypes/-Verzeichnis existiert"
ok test -d "$ARCH_DIR"

it "Vorbedingung: team-rules/tags/-Verzeichnis existiert"
ok test -d "$TAGS_DIR"

it "Vorbedingung: python3 verfügbar"
ok "$PY" -c "import json,sys"

# Liste der zu prüfenden JSON-Files (ohne $schema-Helper-Files; .gitkeep ist kein .json).
mapfile -t ARCH_FILES < <(find "$ARCH_DIR" -maxdepth 1 -type f -name '*.json' | sort)

it "Es gibt mind. die erwarteten Kern-Archetypen (>= 18 *.json)"
ok test "${#ARCH_FILES[@]}" -ge 18

# ── 1. Valides JSON (pro File) ────────────────────────────────────────────────────────────────
for f in "${ARCH_FILES[@]}"; do
  base="$(basename "$f")"
  it "JSON valide: $base"
  ok "$PY" -c "import json,sys; json.load(open(sys.argv[1]))" "$f"
done

# ── Pro-File-Schema/Vollständigkeit (2 + 3 + 4) ─────────────────────────────────────────────
# Wir lassen python pro File einen kompakten, prüfbaren Status-String drucken:
#   "<archetype>|<has_model>|<model>|<model_ok>|<has_tags>|<tags_is_array>|<tags_all_slug>|<has_gateTier>|<bad_tags>"
# und asserten dann je Invariante in bash gegen den erwarteten Wert (eq/contains) — echte Wert-Asserts,
# kein Source-Grep.
archetype_status() {
  "$PY" - "$1" <<'PY'
import json, re, sys
slug = re.compile(r'^[a-z0-9][a-z0-9-]*$')
d = json.load(open(sys.argv[1]))
a = d.get("archetype", "")
has_model = "model" in d
model = d.get("model", "")
model_ok = (model in ("opus", "sonnet", "haiku")) if has_model else True
has_tags = "tags" in d
tags = d.get("tags", None)
tags_is_array = isinstance(tags, list) if has_tags else True
tags_all_slug = (all(isinstance(t, str) and slug.match(t) for t in tags)) if (has_tags and isinstance(tags, list)) else True
bad = ",".join(t for t in (tags or []) if not (isinstance(t, str) and slug.match(t))) if (has_tags and isinstance(tags, list)) else ""
has_gate = "gateTier" in d
def b(x): return "1" if x else "0"
print("|".join([a, b(has_model), str(model), b(model_ok),
                b(has_tags), b(tags_is_array), b(tags_all_slug), b(has_gate), bad]))
PY
}

for f in "${ARCH_FILES[@]}"; do
  base="$(basename "$f")"
  st="$(archetype_status "$f")"
  IFS='|' read -r a has_model model model_ok has_tags tags_is_array tags_all_slug has_gate bad_tags <<<"$st"

  # 2a. model (falls vorhanden) ∈ {opus,sonnet,haiku}
  it "2-schema: model ist {opus|sonnet|haiku} oder absent — $base"
  eq "$model_ok" "1"
  if [ "$has_model" = "1" ]; then
    it "2-schema: model-Wert '$model' ist ein gültiger Enum-Member — $base"
    contains " $MODELS_VALID " " $model "
  fi

  # 2b. tags (falls vorhanden) = Array von Slug-Strings
  it "2-schema: tags ist Array (falls vorhanden) — $base"
  eq "$tags_is_array" "1"
  it "2-schema: alle tags sind Slug-Strings ^[a-z0-9][a-z0-9-]*\$ (bad: [$bad_tags]) — $base"
  eq "$tags_all_slug" "1"

  if printf '%s' "$a" | grep -Eq "$EXEMPT_RE"; then
    # 3-exempt: coworker/human dürfen model UND tags BEIDE fehlen.
    it "3-vollständigkeit: $a (exempt) hat KEIN model"
    eq "$has_model" "0"
    it "3-vollständigkeit: $a (exempt) hat KEINE tags"
    eq "$has_tags" "0"
    # 4: gateTier ist hier bewusst NICHT gefordert (siehe Header-Begründung).
  else
    # 3-vollständigkeit: alle anderen brauchen model UND tags (tags darf leer sein → Feld muss da sein).
    it "3-vollständigkeit: $a hat model"
    eq "$has_model" "1"
    it "3-vollständigkeit: $a hat tags (Feld vorhanden, darf [] sein)"
    eq "$has_tags" "1"
    # 4-regression: gateTier weiterhin da (Phase-A-Schutz).
    it "4-regression: $a hat gateTier (Phase-A-Regression-Schutz)"
    eq "$has_gate" "1"
  fi
done

# ── 5. Tag-Integrität: jeder gelistete Tag hat team-rules/tags/<tag>.md (keine toten Tags) ─────
# Union aller Tags über alle Archetypen einsammeln (python), dann pro Tag File-Existenz asserten.
mapfile -t ALL_TAGS < <(
  "$PY" - "${ARCH_FILES[@]}" <<'PY'
import json, sys
tags = set()
for p in sys.argv[1:]:
    d = json.load(open(p))
    for t in d.get("tags", []) or []:
        if isinstance(t, str):
            tags.add(t)
for t in sorted(tags):
    print(t)
PY
)

it "5-tag-integrität: es wurden überhaupt Tags eingesammelt (sanity)"
ok test "${#ALL_TAGS[@]}" -ge 1

for t in "${ALL_TAGS[@]}"; do
  it "5-tag-integrität: team-rules/tags/$t.md existiert (kein toter Tag)"
  ok test -f "$TAGS_DIR/$t.md"
done

summary
