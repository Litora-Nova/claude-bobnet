# team-rules/tiers.md — Circle-of-Trust 4-Tier-Matrix (Engine-Canon)

> Quelle der Wahrheit für die Risiko-Tiers. **Daten vor Code:** `bin/tier <rolle>` + Reviews lesen DAS hier.
> Tokens: `{TEAM_LEAD}` = der Projekt-Lead, `{HUMAN}` = der Product Owner.
> Projekt-Override: `_dev_team/team-rules/tiers.md` schlägt diese Engine-Datei — **aber T4 bleibt Floor** (s.u.).

## Matrix (Risiko → Gate → Autonomie)

<!-- TIER:1 -->**T1 — Text / Copy / Brand / i18n.** Gate: Review-30s-Tick + CI grün. → `{TEAM_LEAD}` autonom bis Staging.
<!-- TIER:2 -->**T2 — Feature (Frontend / Backend).** Gate: Review + Tests + Release-Pre-Flight, CI grün. → `{TEAM_LEAD}` autonom bis Staging.
<!-- TIER:3 -->**T3 — Security / Migration / Dependencies / Egress.** Gate: voller Circle inkl. Compliance, CI grün. → `{TEAM_LEAD}` autonom bis Staging **nach GRÜN**.
<!-- TIER:4 -->**T4 — Production / DNS / Secrets / force-push & History-Rewrite.** Gate: alles + ausdrückliches `{HUMAN}`-OK. → **NUR `{HUMAN}` (human-only, harte Grenze).**

## Push- & Deploy-Leitplanken (PO-Doktrin 2026-06-10)

| Aktion | Stufe | Verhalten |
|---|---|---|
| `git fetch/pull/push` auf Arbeits-Branches (development/staging/Feature) | frei | Push = Standard, Teil jeder Sync-Routine (`sync.md`) |
| Push auf den **Live-Branch** (der Branch, der die laufende App/Site/Service repräsentiert — je nach Projekt `main`/`master`/`production`) | Absprache | nur nach expliziter Absprache mit dem `{HUMAN}` |
| **Deploy-Config-Edits** (`config/deploy.rb`, `config/deploy/*` inkl. Templates, `Capfile`, `configuration.yml`) | ask | Agent schlägt den konkreten Edit vor, `{HUMAN}` bestätigt **jeden Edit einzeln** (deploy-guard „ask" — nie wegautomatisieren). Wert-Anpassungen ja, **keine strukturellen Umbauten**. |
| **Staging-Deploy** (Ausführung, z. B. `cap staging …`) | Erlaubnis pro Aktion | möglich, aber NUR auf **ausdrückliche `{HUMAN}`-Erlaubnis pro Aktion/Änderung** — Ansage/Heartbeat allein reicht nicht. Keine Allow-Regel in Settings (würde den Prompt wegautomatisieren). |
| **Production-Deploy** (Ausführung, z. B. `cap production …`) | T4 / Deny | Default: nur der `{HUMAN}` selbst. Einzige Ausnahme: das Remote-Go-Protokoll (unten) für Apps mit `remote-ok`. |
| force-push / History-Rewrite / Remote-Branch-Delete / DNS / Secrets | T4 / Deny | nie autonom, keine Ausnahme. |

**Projekt-HARD-Rules bleiben unberührt** und überschreiben diese generelle Policy — immer in
Richtung strenger (z. B. „Push erst nach `{HUMAN}`-GO" in einem Kundenprojekt).

## Remote-Go-Protokoll für Production-Deploys (per-App opt-in)

Für den Fall, dass der `{HUMAN}` einen Production-Deploy nur fern anstoßen kann (z. B. vom Telefon):

- **Per-App-Schalter** in `team.config.json`: `"prodDeploy": "remote-ok" | "human-only"` —
  **Default `human-only`**. Der `{HUMAN}` entscheidet einmal pro App, ob sie für den Fern-Anstoß
  geeignet ist (Migrationsrisiko / Rollback-Story / Reife).
- **Ablauf — alle Schritte vom `{HUMAN}` über seinen authentifizierten Kanal** (Messenger-Chat-ID /
  Dashboard-Approval). Ein Agent, der ein GO *weiterreicht*, zählt NICHT (Relay ≠ `{HUMAN}`-GO):
  1. **Anstoß** — „prod deploy <app>".
  2. **Bestätigung 1 (Inhalt)** — Lead antwortet mit Pre-Deploy-Summary (Branch/Commit,
     Migrationen ja/nein, Gates grün); `{HUMAN}` bestätigt den Inhalt.
  3. **Bestätigung 2 (Aktion)** — scharfe Frage: „Production-Deploy <app> @<commit> — wirklich?".
  4. **Wörtliches „Go!"** als separate Nachricht → erst dann läuft die Ausführung.
- **Sicherungen:** Bestätigungen verfallen (TTL ~10 min) · Reihenfolge strikt, Abweichung = Abbruch ·
  volles Audit-Artefakt (wer/wann/Commit/alle drei Bestätigungen) im Standup.
- Es werden **keine Gates übersprungen** — nur die Ausführung ist delegiert. Maschinelle
  Durchsetzung = Deploy-Runbook (Issue #20); bis dahin gilt das Protokoll als bindende Konvention,
  der Deny auf direkte `cap production`-Aufrufe bleibt davon unberührt.

## T4 = nicht-überschreibbarer Floor

T4 ist die EINE harte Grenze. Der **`deploy-guard`-Hook setzt sie maschinell durch — zweistufig:**

- **Block (Exit 2):** Secrets/Credentials (`.secrets/`, `master.key`, `credentials.yml.enc`,
  `*.env.production`), shared Deploy-Recipes (`recipes2go`) und Production-Infra — `{HUMAN}`-only,
  Edit nie erlaubt (`team-rules/deploy-guard.paths`).
- **Ask:** Deploy-Configs (`config/deploy.rb`, `config/deploy/*`, `Capfile`, `configuration.yml`) —
  Edit nur mit expliziter `{HUMAN}`-Bestätigung pro Edit (PO-Doktrin 2026-06-15: der Bob editiert,
  der `{HUMAN}` bestätigt jeden Edit; `team-rules/deploy-guard.ask.paths`).

Ein Projekt-Override darf beides nur **erweitern bzw. verschärfen** (ask→block ok), nie lockern —
die Kern-Globs merged der Hook IMMER dazu (t4_floor/ask_floor). **Autonomie-Stufen T1–T3 sind
projekt-justierbar; T4 nicht.**
