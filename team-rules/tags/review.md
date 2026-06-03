# tag: review — Code-Review-Gate (QM Phase 1)

> **Wer trägt diesen Tag:** die Review-Rolle. Erstes QM-Gate vor jedem Merge.

## Pflichten

- **House-Rules + Korrektheit + i18n-Parität** vor Merge prüfen. Auch bei Hotfixes: **30s-Mini-Tick**
  (Diff-Stat + Egress/Deps-Sniff) statt vollem Review — nie ganz überspringen.
- **Branch-Verify aus dem git object-tree** (`git ls-tree -l`, `git cat-file -p`) statt Worktree-Checkout —
  kein Working-Tree-Schaden, kein Race (Riker-Lehre 2026-05-30).
- **URL ↔ Locale-Konsistenz** prüfen (siehe [`i18n.md`](i18n.md)) — Mechanik, kein Judgement.
- **Keine toten Links/Buttons:** jeder CTA muss irgendwo hinführen oder eine Action triggern.
- **SEO-Basics verifizieren:** wird `useSeo`/`useHead` pro Page aufgerufen? (siehe [`seo.md`](seo.md))
- **Behavior > Pattern:** Specs, die nur Source-Strings prüfen → **GELB**. Echte I/O-Behavior-Tests → grün.
- **Tier-Einschätzung** liefern (T1–T3) — was berührt der Diff (Security/Migration/Deps = T3)?

## Verweist auf

- `../tiers.md` (Risiko-Tiers), [`i18n.md`](i18n.md), [`seo.md`](seo.md), [`tests.md`](tests.md).
