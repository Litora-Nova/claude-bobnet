# archetypes/ — Rollen-Definitionen (Schicht ① Struktur)

*Was* eine Rolle tut — universal, versioniert, themen-unabhängig. Kein Name/Emoji/Bio
(das ist [Theme](../themes/)). Validiert gegen [`schemas/archetype.schema.json`](../schemas/archetype.schema.json).

| Archetyp | category | ring | Gate-Tier | Model-Tier | Bobiverse-Persona (Beispiel-id) |
|---|---|---|---|---|---|
| `techlead` | bob | core | — | HEAVEN | Bob (`BOB-techlead`) |
| `backend` | bob | inner | — | HEAVEN | Bill (`BOB-backend`) |
| `frontend` | bob | inner | — | HEAVEN | Luke (`BOB-frontend`) |
| `website` | bob | inner | — | HEAVEN | Linus (`BOB-website`) |
| `design` | bob | inner | — | HEAVEN | *(component-first Design)* |
| `review` | bob | gate | 1–3 | Cruiser | Riker (`BOB-review`) |
| `compliance` | bob | gate | 3 | HEAVEN | Dexter (`BOB-compliance`) |
| `tests` | bob | gate | 2–3 | Cruiser | Marvin (`BOB-tests`) |
| `release` | bob | gate | 2–4 | Cruiser | Bender (`BOB-release`) |
| `dashboard` | service | outer | — | HEAVEN | Garfield (`BOB-dashboard`) |
| `docs` | bob | outer | — | Cruiser | Homer (`BOB-docs`) |
| `content` | bob | outer | — | Cruiser | Bridget (`BOB-content`) |
| `hiwi` | bob | on-demand | 1–3 | Probe | Mario (`BOB-hiwi`) — Routinen-/Runbook-Executor |
| `explainer` | bob | outer | 1 | Cruiser | Howard (`BOB-explainer`) — read-only App-Explainer |
| `support` | bob | outer | 1 | Cruiser | *(reserviert)* — Ticket-Triage |
| `marketing` | bob | outer | — | HEAVEN | *(geplant)* |
| `plan-judge` | service | gate | goal | Cruiser | Anek (`SVC-plan-judge`) — Hüter des GOAL |
| `process-auditor` | service | gate | prozess | Cruiser | *(Colonel Butterworth)* |
| `guppi` | service | shared | — | Probe | GUPPI (`SVC-guppi`) — Routine + Concierge |
| `coworker` | coworker | outer | — | — | *(externe Instanz, `EXT-*`)* |
| `human` | human | core | — | — | Owner (`HUMAN-bob`) |
| `roamer` | helper | on-demand | — | Probe | ROAMER 🕷️ (ephemer, kein Roster) |
| `sonde` | helper | on-demand | — | Probe | Sonde 🛰️ (ephemer, kein Roster) |
| `advisor` | helper | on-demand | — | HEAVEN (`fable`) | Advisor 🦉 (ephemer, kein Roster) |

**Neu in Phase 2:** `support`, `marketing`, `process-auditor` (Butterworth). **Helper** (`roamer`/`sonde`/`advisor`)
+ **service** (`guppi`/`plan-judge`) erscheinen nicht im Roster-Bauer-Grid — sie sind ephemer bzw. laufen
als Badge/Daemon/Event-getriggert.

**Roster-Kanon (PO-bestätigt):** der vollständige Folder-Bobiverse-Roster + UID-Schema + die
besondere Mechanik von `plan-judge` (Anek), `hiwi` (Mario, Routinen-Executor), `guppi` (Concierge) und
`explainer` (Howard) stehen in [`../team-rules/roster.md`](../team-rules/roster.md). **Howard ist jetzt der
read-only `explainer`** (löst die Support-Kollision); `support` bleibt Ticket-Triage (Persona reserviert).

Die `id` (z. B. `BOB-techlead`) verbindet Archetyp ↔ Theme-Persona ↔ Instanz — siehe [`schemas/README.md`](../schemas/README.md).

## Phase C — Tags, Model, Pflichten (Plan §9)

Jeder Archetyp trägt jetzt zusätzlich (additiv, `gateTier` unangetastet):

- **`tags[]`** — Area-/Pflicht-Tags. Geteilte Anweisungen leben **einmal** pro Tag in
  [`../team-rules/tags/<tag>.md`](../team-rules/tags/) (kein Duplizieren pro Agent). Der Agent-Init lädt
  Rolle (Archetyp) + die `.md` zu jedem seiner Tags. Der Tag **`dev`** ist der Bauer-Marker → löst
  TDD + Kommentare aus.
- **`model`** — konkretes Provider-Model, explizit pro Archetyp (Fallback über `modelTier`:
  HEAVEN→`opus`, Cruiser→`sonnet`, Probe→`haiku`). **Cut seit Sonnet 5 (PO 2026-07-02):**
  `opus`/xhigh nur noch für `techlead` + `design`; die generativen Team-Bobs (backend/frontend/
  dashboard/website/marketing) und `compliance` fahren `sonnet`/xhigh — Sonnet 5 liefert nahe
  Opus-Qualität bei Coding/Agentic zu ~40% des Preises. Gates bleiben `sonnet`/high, Helfer +
  Service `haiku`/low. **`fable`** (Mythos-Class, ~2× Opus) ist dem `advisor` vorbehalten bzw.
  bewusster Override (`BOBNET_MODEL_OVERRIDE=fable`). `coworker`/`human` haben kein `model`
  (extern/Mensch, keine von uns gespawnte Provider-Instanz). Instanz/Theme darf überschreiben —
  Kosten/Qualität-Tuning ist PO-Call.
- **`duties[]`** — beginnen mit Heartbeat + Circle-of-Trust und referenzieren die Tag-Dateien
  (`dev: … siehe tags/dev.md`) statt deren Inhalt zu duplizieren.

**Tag-Map (Stand Phase C):** backend `{backend,dev,db,api}` · frontend `{frontend,js,dev,i18n}` ·
website `{website,js,dev,i18n,seo}` · content `{content,i18n,dev}` · hiwi `{dev}` ·
review `{review}` · compliance `{compliance}` · tests `{tests}` · release `{release}` ·
dashboard `{dashboard,js,dev}` · docs `{docs}` · support `{docs}` · explainer `{docs}` ·
marketing `{content,i18n,seo}` · process-auditor `{process}` · plan-judge `{goal}` · techlead `{docs}` ·
guppi `{ops}` · roamer/sonde/advisor `{}` (ephemer).

**Spawn-UID vs. Archetyp-id:** die `idPattern` hier (`BOB-backend`) ist die themen-unabhängige
Persona-Bindung. Die **Spawn-Instanz** im BobNet bekommt zusätzlich eine projekt-präfixierte UID
`<PROJECT_UID>-<role>` (z.B. `acme-backend-dev`) — Details in [`../CONVENTIONS.md`](../CONVENTIONS.md) §1a.
