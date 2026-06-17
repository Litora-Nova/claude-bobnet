---
paths:
  - "schemas/**"
  - "archetypes/**"
  - "VERSION"
  - "SCHEMA_VERSION"
---

# Changing the instance contract

- **Breaking changes** — bump `VERSION` (SemVer, for humans/changelog) and/or `SCHEMA_VERSION`
  (integer, the machine compat anchor) when you change the instance contract. Run
  `bin/check-compat` to verify engine↔instance schema compatibility before shipping a schema bump.
- The 3-layer split still applies (see core `CLAUDE.md` §2): structure/behavior → archetype;
  look/labels → theme; never bake project state into the engine.
- Archetypes validate against `schemas/archetype.schema.json` — keep new fields schema-valid.
