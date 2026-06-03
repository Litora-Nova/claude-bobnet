# team-rules/tiers.md — Circle-of-Trust 4-Tier-Matrix (Engine-Canon)

> Quelle der Wahrheit für die Risiko-Tiers. **Daten vor Code:** `bin/tier <rolle>` + Reviews lesen DAS hier.
> Tokens: `{TEAM_LEAD}` = der Projekt-Lead, `{HUMAN}` = der Product Owner.
> Projekt-Override: `_dev_team/team-rules/tiers.md` schlägt diese Engine-Datei — **aber T4 bleibt Floor** (s.u.).

## Matrix (Risiko → Gate → Autonomie)

<!-- TIER:1 -->**T1 — Text / Copy / Brand / i18n.** Gate: Review-30s-Tick + CI grün. → `{TEAM_LEAD}` autonom bis Staging.
<!-- TIER:2 -->**T2 — Feature (Frontend / Backend).** Gate: Review + Tests + Release-Pre-Flight, CI grün. → `{TEAM_LEAD}` autonom bis Staging.
<!-- TIER:3 -->**T3 — Security / Migration / Dependencies / Egress.** Gate: voller Circle inkl. Compliance, CI grün. → `{TEAM_LEAD}` autonom bis Staging **nach GRÜN**.
<!-- TIER:4 -->**T4 — Production / DNS / Secrets.** Gate: alles + ausdrückliches `{HUMAN}`-OK. → **NUR `{HUMAN}` (human-only, harte Grenze).**

## T4 = nicht-überschreibbarer Floor

T4 ist die EINE harte Grenze. **`team-rules/deploy-guard.paths` ist die maschinelle Durchsetzung von T4** —
der `deploy-guard`-Hook blockt Edits an Production-/Deploy-/Secret-Pfaden (Exit 2). Ein Projekt-Override darf
den Schutz nur **erweitern**, nie die T4-Kern-Globs (`.secrets/`, `master.key`, `credentials.yml.enc`,
`*.env.production`, `config/deploy/*`, `Capfile`) entfernen. **Autonomie-Stufen T1–T3 sind projekt-justierbar; T4 nicht.**
