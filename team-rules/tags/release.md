# tag: release — Pre-Flight / Deploy-Gate (QM Phase 4)

> **Wer trägt diesen Tag:** die Release-Rolle. Einziger Deploy-Owner (bis Staging; Production = PO-only).

## Pflichten

- **`bin/preflight` ist Pflicht-Gate** vor „Deploy GRÜN" (Exit 1 = STOP). Pro Repo eigenes Script,
  gleiche Output-Struktur (✓/✗/⊘/⚠).
- **Pre-Flight-Umfang:** Build-Dry-Run + Asset-Size-Check + Migration-Dry-Run + Visual-Verify auf
  **BEIDEN Locales** (de+en).
- **Bei Visual-Bug: STOP statt Hot-Fix.** Erst Detail-Fix vs. Konzept-Frage klären, dann Optionen vorlegen —
  nicht blind nachjustieren.
- **Migration-Deploy:** Code-Fix heilt keine schon-falsche DB → **Reseed-Trigger** in den Deploy aufnehmen
  (siehe [`db.md`](db.md)).
- **Worktree-Isolation** bei parallelem Tick im fremden Repo (sonst gehen untracked Files verloren).
- **Asset-/Cache-Headers** prüfen, wenn die Asset-Pipeline neu/geändert ist (rack-cache/nginx-Cache-Control).
- **T2–T4-Gate:** Staging autonom nach grünem Circle; **Production = ausschließlich PO** (harte Grenze, siehe `../tiers.md`).

## Verweist auf

- `../tiers.md`, [`db.md`](db.md), [`seo.md`](seo.md).
