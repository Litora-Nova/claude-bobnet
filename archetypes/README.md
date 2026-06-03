# archetypes/ — Rollen-Definitionen (Schicht ① Struktur)

*Was* eine Rolle tut — universal, versioniert, themen-unabhängig. Kein Name/Emoji/Bio
(das ist [Theme](../themes/)). Validiert gegen [`schemas/archetype.schema.json`](../schemas/archetype.schema.json).

| Archetyp | category | ring | Gate-Tier | Model-Tier | Bobiverse-Persona (Beispiel-id) |
|---|---|---|---|---|---|
| `techlead` | bob | core | — | HEAVEN | Bob (`BOB-techlead`) |
| `backend` | bob | inner | — | Cruiser | Bill (`BOB-backend`) |
| `frontend` | bob | inner | — | Cruiser | Luke (`BOB-frontend`) |
| `website` | bob | inner | — | Cruiser | Linus (`BOB-website`) |
| `review` | bob | gate | 1–3 | Cruiser | Riker (`BOB-review`) |
| `compliance` | bob | gate | 3 | Cruiser | Marvin (`BOB-compliance`) |
| `tests` | bob | gate | 2–3 | Cruiser | Dexter (`BOB-tests`) |
| `release` | bob | gate | 2–4 | Cruiser | Bender (`BOB-release`) |
| `dashboard` | service | outer | — | Cruiser | Garfield (`BOB-dashboard`) |
| `docs` | bob | outer | — | Cruiser | Homer (`BOB-docs`) |
| `content` | bob | outer | — | Cruiser | Bridget (`BOB-content`) |
| `hiwi` | bob | on-demand | — | Cruiser | Mario (`BOB-hiwi`) |
| `support` | bob | outer | — | Cruiser | *(reserviert: Howard)* |
| `marketing` | bob | outer | — | Cruiser | *(geplant)* |
| `process-auditor` | bob | gate | prozess | Cruiser | *(Colonel Butterworth)* |
| `guppi` | service | shared | — | Probe | GUPPI (`SVC-guppi`) |
| `coworker` | coworker | outer | — | — | Henry / Tim (`EXT-*`) |
| `human` | human | core | — | — | Austin (`HUMAN-bob`) |
| `roamer` | helper | on-demand | — | Probe | ROAMER 🕷️ (ephemer, kein Roster) |
| `sonde` | helper | on-demand | — | Probe | Sonde 🛰️ (ephemer, kein Roster) |

**Neu in Phase 2:** `support`, `marketing`, `process-auditor` (Butterworth). **Helper** (`roamer`/`sonde`)
+ **service** (`guppi`) erscheinen nicht im Roster-Grid — sie sind ephemer bzw. laufen als Badge/Daemon.

Die `id` (z. B. `BOB-techlead`) verbindet Archetyp ↔ Theme-Persona ↔ Instanz — siehe [`schemas/README.md`](../schemas/README.md).

## Phase C — Tags, Model, Pflichten (Plan §9)

Jeder Archetyp trägt jetzt zusätzlich (additiv, `gateTier` unangetastet):

- **`tags[]`** — Area-/Pflicht-Tags. Geteilte Anweisungen leben **einmal** pro Tag in
  [`../team-rules/tags/<tag>.md`](../team-rules/tags/) (kein Duplizieren pro Agent). Der Agent-Init lädt
  Rolle (Archetyp) + die `.md` zu jedem seiner Tags. Der Tag **`dev`** ist der Bauer-Marker → löst
  TDD + Kommentare aus.
- **`model`** — konkretes Provider-Model (maschinen-lesbare Auflösung von `modelTier`):
  **HEAVEN→`opus`** (Tech-Lead), **Cruiser→`sonnet`** (alle Team-/QM-Bobs), **Probe→`haiku`**
  (Helfer roamer/sonde + Service guppi). `coworker`/`human` haben kein `model` (extern/Mensch, keine
  von uns gespawnte Provider-Instanz). Instanz/Theme darf überschreiben — Kosten/Qualität-Tuning ist PO-Call.
- **`duties[]`** — beginnen mit Heartbeat + Circle-of-Trust und referenzieren die Tag-Dateien
  (`dev: … siehe tags/dev.md`) statt deren Inhalt zu duplizieren.

**Tag-Map (Stand Phase C):** backend `{backend,dev,db,api}` · frontend `{frontend,js,dev,i18n}` ·
website `{website,js,dev,i18n,seo}` · content `{content,i18n,dev}` · hiwi `{dev}` ·
review `{review}` · compliance `{compliance}` · tests `{tests}` · release `{release}` ·
dashboard `{dashboard,js,dev}` · docs `{docs}` · support `{docs}` · marketing `{content,i18n,seo}` ·
process-auditor `{process}` · techlead `{docs}` · guppi `{ops}` · roamer/sonde `{}` (ephemer).

**Spawn-UID vs. Archetyp-id:** die `idPattern` hier (`BOB-backend`) ist die themen-unabhängige
Persona-Bindung. Die **Spawn-Instanz** im BobNet bekommt zusätzlich eine projekt-präfixierte UID
`<PROJECT_UID>-<role>` (z.B. `acme-backend-dev`) — Details in [`../CONVENTIONS.md`](../CONVENTIONS.md) §1a.
