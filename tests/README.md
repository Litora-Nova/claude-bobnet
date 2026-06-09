# tests/ — Engine-Behavior-Specs (Dexter / QA-Gate)

Unabhängige Black-Box-Specs für die Engine-Shell-Scripts. **Behavior > Source-Pattern:**
die Specs leben getrennt von den Scripts, rufen sie als Black-Box auf und asserten gegen
das in `team-rules/*.md` + den Script-Headern beschriebene **SPEC-Verhalten** — nicht gegen
die Implementierung. So fängt das Gate Drift, statt ihn mitzudriften.

## Ausführen

```bash
bash tests/run.sh                       # alle *_spec.sh, aggregiertes Gate (Exit 0=grün/1=rot)
bash tests/run.sh git_identity_spec.sh  # gezielt
bash tests/git_identity_spec.sh         # einzeln (eigenes summary + Exit-Code)
```

## Konventionen

- Eine Spec pro Script: `<name>_spec.sh`. Quelle der Asserts steht im Spec-Header.
- **Alle Fixtures in `mktemp -d`** (Wegwerf-Theme/-Archetypen/-Env/-Registry/-standup).
  NIE in die echte `projects.registry.json`, echte `themes/*/theme.json` oder echte standup-Inboxen schreiben.
- `_helper.sh` = minimales Harness (`it`/`ok`/`eq`/`contains`/`file_has`/`summary`).
- Eingebaute `--self-test`-Modi der Scripts werden NICHT als Gate gewertet (self-confirming),
  nur als zusätzlicher Sanity-Check mitgeführt.

## Abgedeckt (Phase D)

| Script | Spec | Schwerpunkte |
|---|---|---|
| `scripts/git-identity.sh` | `git_identity_spec.sh` | Format-String (mit/ohne role), i18n de/en, trailer, export(author/both), role-Fallback-Kette, Edges: fehlendes positionLabel/PROJECT_NAME/Email/theme.json, unbekannter Name → rc!=0; Integration gegen echte `bobiverse/theme.json` |
| `scripts/scut-router.sh` | `scut_router_spec.sh` | gerichtet `@X`/`[uid]`/`[uid]@X` → Inbox, TEAM_LEAD-Default, ungerichtet → Review-Queue, DRYRUN, Robustheit gegen malformed/leere Events, fehlende Registry |
| `dashboard/server/api/*.post.ts` + `utils/tenant.ts` | `dashboard_tenant_scope_spec.sh` | **Tenant-Leak-Regression-Guard** (lokaler Task #13): ?project=X trifft NUR X's standupDir (Zwei-Tenant-mktemp-Registry, Schreibziele disjunkt, Write leakt nicht in B) · unbekanntes project → 404-Pfad (kein stiller Fallback) · Quell-Invariante: alle tenant-gescopeten Writes leiten ihr Dir aus `tenantOf(event)` ab, kein direkter `envTenant()` im Write · Live (read-only, skip-grün): POST resolve ?project=`<unbekannt>` → 404 vor dem Write (KEINE Live-Tenant-Mutation) |

## Coverage-Gap (Stand Phase D) — siehe Handoff an Bob

Noch OHNE eigene Spec (Channel-Adapter + Poller):
`scripts/channels/{telegram,email,github,teams}.sh`, `scripts/scut-poll.sh`, `scripts/scut.sh`,
`scripts/qa-add.sh`. Begründung + Priorisierung im Dexter-Handoff.
