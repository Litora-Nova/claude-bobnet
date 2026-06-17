---
paths:
  - "tests/**"
---

# Working in tests/

- The **test gate** lives here: run `bash tests/run.sh` (exit 0 = green, 1 = red; pass a spec
  name to run a single spec). Specs are **black-box behavior tests** against the documented spec,
  kept separate from the scripts (**behavior > source-pattern**).
- **New behavior → new/updated spec.** Some scripts also expose a `--self-test` mode for a quick
  sanity check, but those are **not** counted as the gate (self-confirming).
- Per-role test conventions: [`team-rules/tags/tests.md`](../../team-rules/tags/tests.md).
