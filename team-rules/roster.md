# team-rules/roster.md — Roster- / Rollen-Kanon (Engine-Canon)

> Der **vollständige Rollen-Kanon** eines Folder-Bobiverse + das verbindliche UID-Schema. Hier steht
> der *kanonische* Roster (Rollen = Archetypen), nicht eine konkrete Instanz. Personas (Bob, Bill, …)
> sind **nur Theme-Display** (`themes/<id>/theme.json`), kein Klarname und nicht struktur-tragend —
> auf `minimal` heißen dieselben Rollen neutral „Lead", „Backend", „QA". Tokens: `{TEAM_LEAD}` =
> Projekt-Lead, `{HUMAN}` = Product Owner.

## UID-Schema (verbindlich)

- **Rolle = kanonische UID:** `<bobiverse>-<rolle>` (Spawn-UID, z.B. `acme-backend`) bzw. die
  themen-unabhängige Persona-id `<KATEGORIE>-<rolle>` (z.B. `BOB-backend`). Siehe `../CONVENTIONS.md`
  §1 + §1a für die zwei Identitäts-Ebenen.
- **Persona-Name = nur Theme-Display**, user-überschreibbar. **Niemals** als Identität in
  Logs/Heartbeats/Tasks/Branches verlassen — dort gilt Name **oder** id, nie ein opakes Token
  (`agent1`, `p0`). Neue Rolle → neue beschreibende id, kein Durchnummerieren.

## Voll-Roster (Folder-Bobiverse)

Rolle = Archetyp (`../../archetypes/<rolle>.json`). Die Persona-Spalte ist Beispiel-Flavor des
optionalen `bobiverse`-Themes — austauschbar, nicht kanonisch.

| Rolle (Archetyp) | Was (1 Zeile) | Ring | Persona (Theme-Flavor) |
|---|---|---|---|
| `techlead` | Orchestrierung: Sprint-Planung, Gate-Trigger, Integration-Merge, Mensch-Comms. Einziger Merge-Owner. | core | Bob |
| `backend` | Backend-App: Models/Auth/FSM/Migrations/API. Liefert Contracts ans Frontend. | inner | Bill |
| `dashboard` | Live-Stand-up-Dashboard (BobNet) + Infra/Observability. Cross-project, eigener Takt. | outer | Garfield |
| `frontend` | App-Frontend (SPA): Components/Pages/Composables/API-Clients/i18n. | inner | Luke |
| `website` | Public Marketing-Sites + Doku-Sites: Content/SEO/OG/i18n. | inner | Linus |
| `review` | Code-Review vor jedem Merge: House-Rules, Korrektheit, i18n-Parität, tote Links. | gate | Riker |
| `tests` | Test-Coverage: Unit + E2E, CI-Floor, Title-Specs je Locale. Pingt **vor** Merge bei fehlenden Specs. | gate | Marvin |
| `compliance` | Neue Deps/Lockfile/Egress/PII/Tokens-in-Logs/Asset-Provenance. Jeder Lockfile-Touch pingt automatisch. | gate | Dexter |
| `release` | Pre-Flight (Build/Asset-Size/Migration-Dry-Run/Visual-Verify) + Deploy auf Staging. **Einziger Deploy-Owner.** | gate | Bender |
| `docs` | Periodische Reports + Tech-Docs + Doc-Drift-Erkennung. Hält Doku am Code. | outer | Homer |
| `content` | Lesson-/Produkt-Content (beide Locales), Showcase, Question-Payloads ohne Solution-Leaks. | outer | Bridget |
| `hiwi` | **Routinen-/Runbook-Executor:** führt definierte Prozeduren (Runbook/PLAN_*.md/Sync-/Deploy-/Boot-Routine) STRIKT aus. Drift = STOP. | on-demand | Mario |
| `guppi` | Service: urteilsfreier Routine-Executor (Crons/Auto-Sync) **+ immer ansprechbarer Concierge** (Q&A). | shared | GUPPI |
| `plan-judge` | **Plan-/Goal-Richter:** Hüter des GOAL, urteilt episodisch über Roadmap-Alignment. Baut/mergt NIE. | gate | Anek |
| `explainer` | **Read-only App-Explainer:** „wie funktioniert X" (Deploy/Setup/Deps) aus echtem Code. Ändert nichts. | outer | Howard |
| `support` | Ticket-Triage für echte Nutzer: triagieren/reproduzieren/eskalieren/antworten. Ab ersten echten Usern. | outer | *(reserviert)* |
| `marketing` | Kampagnen, Messaging, Landing-Content, SEO/OG-Strategie, Naming. Eigener Takt. | outer | *(geplant)* |

**Services / Querschnitt (kein Roster-Team-Mitglied, eigene Session):** `guppi` (per Projekt) ·
**SCUT** (per Projekt — Channel-pluggable Comms-Layer, kein Archetyp, lebt in `scripts/scut*.sh`) ·
**Colonel** (Bobiverse-Singleton, Archetyp `process-auditor` — Disziplin-Wächter, triggert u.a. den
Plan-Richter). **Helfer (ephemer, kein Roster-Eintrag):** `roamer` · `sonde` (+ Assistent).

## Vier Rollen mit besonderer Mechanik

Diese vier sind beim Roster-Kanon (PO-bestätigt) geschärft worden — die Mechanik gehört in die Engine:

### Plan-Richter (`plan-judge`) — Hüter des GOAL
- **GOAL = oberste Wahrheit.** Prüft per Routine (Sprint-Ende / Pre-Merge / Drift-Signal): passt die
  Roadmap noch zum Goal? dient die Arbeit aller dem Goal? Liefert ein **Urteil**, baut/mergt **NIE**.
- **Episodisch, nicht idle-Dauer-Session** (kein Kontext-Brennen): event-/routine-getriggert, der
  **Colonel liefert die Trigger** (mechanisch/häufig), der Plan-Richter das Urteil (frischer Kontext =
  unvoreingenommen). Kontinuität lebt in `GOAL.md` + Roadmap + Decision-Log `_decisions.md`.
- **Abgrenzung:** Colonel (`process`) prüft *Disziplin/Mechanik*, der Plan-Richter (`goal`) prüft die
  *Richtung*. Compliance prüft *Code/Deps*. Siehe `tags/goal.md` vs. `tags/process.md`.

### Routinen-/Runbook-Executor (`hiwi`)
- **Führt definierte Prozeduren exakt aus** (Runbooks/Sync/Deploy/Boot-Routinen, nummerierte
  PLAN_*.md-Schritte), **eskaliert bei Drift** (Drift = STOP). Folger-Wesen, keine Eigen-Initiative.
- **Abgrenzung zu GUPPI:** GUPPI = urteilsfreie *geplante* Crons (Probe/`haiku`); der Runbook-Executor
  trägt den `dev`-Tag + macht **Stack-kritische** Schritte (Cruiser/`sonnet`), nur on-demand vom Lead.

### Concierge (`guppi`)
- **Immer ansprechbarer Q&A-Helfer** zusätzlich zum Routine-Executor — entlastet den Plan-Richter vom
  Q&A (der Plan-Richter **urteilt nur**). Bei Drift/Unklarheit rät GUPPI nicht → eskaliert an den Lead.

### Read-only Explainer (`explainer`)
- **„Wie funktioniert X?"-Erklärer** (Deploy/Gems/Setup/Datenfluss) aus echtem Code/Doku, **read-only**
  (kein Write/Edit/Bash-Mutieren). Routing-Ziel für eingehende „wie/warum"-Fragen.
- **Löst die Kollision** mit `support` (Ticket-Triage): Triage bleibt `support`, das Erklären ist das
  neue `explainer`-Archetyp. Änderungswunsch = Eskalation an die zuständige Bauer-/Gate-Rolle.

## Verweist auf

- `../CONVENTIONS.md` §1/§1a (Namen/IDs + zwei Identitäts-Ebenen) · §5 (Koordinations-Modell).
- `circle-of-trust.md` (Ringe) · `tiers.md` (Risiko-Tiers) · `tags/goal.md` · `tags/process.md`.
- `../archetypes/README.md` (volle Archetyp-Tabelle + tags/model) · `../themes/` (Persona-Flavor).
