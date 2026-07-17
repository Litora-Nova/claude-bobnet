# team-rules/commits.md — Commit-Authorship (beschreibende Regel)

> Diese Datei ist die **Daten-/Regel-Quelle** für `scripts/git-identity.sh`. Das Script resolved
> die Commit-Identität eines Agenten aus `theme.json` (name + positionLabel) + `dev-team.env`
> (`PROJECT_NAME` als Display + `DEV_TEAM_EMAIL`) — **kein Hardcode**. **Regel ändern = hier
> (Daten) editieren, nicht im Script.** Projekt-Override: gleichnamiges File unter
> `_dev_team/team-rules/commits.md` (Engine = Fallback).

## Kanon (PO 2026-06-02, final)

Jeder Commit eines Agenten trägt **eine Commit-Identität mit einer geteilten Team-Email**:

```
<Name> (<Projekt-Display> <role>) <DEV_TEAM_EMAIL>
```

- **Name** = Persona-Name (`theme.json` → `personas.<id>.name`, z.B. `Garfield`).
- **Projekt-Display** = mutabler Anzeige-Name des Projekt-Bobiverse (`dev-team.env` → `PROJECT_NAME`,
  z.B. `Acme Inc`, `Claude-tools`). **NICHT** die immutable `PROJECT_UID`.
- **role** = Persona-Rollen-Label (`theme.json` → `personas.<id>.positionLabel`, z.B. `BobNet Architect`).
  Fehlt `positionLabel`, fällt es auf das Archetyp-`positionLong` (z.B. `Stand-up-Dashboard (BobNet)`) zurück.
- **Email** = **EINE geteilte** `DEV_TEAM_EMAIL` für **ALLE** Repos (`dev-team.env`, Default
  `team@litora-nova.com`). Kein per-Agent-Split, kein per-Repo-`includeIf`.

Beispiele:

```
Bob (Acme Inc team-lead) <team@litora-nova.com>
Garfield (Claude-tools BobNet Architect) <team@litora-nova.com>
Bill (Acme Inc Backend + Infra) <team@litora-nova.com>
```

## Author vs. `Co-Authored-By:`-Trailer — KONTEXTABHÄNGIG (PO 2026-06-02, geklärt)

Der PO hat es präzisiert: **es ist nicht entweder/oder, sondern hängt davon ab, wer committet:**

| Situation | Mechanik | Wer steht wo |
|---|---|---|
| **Solo** — der Agent committet seine eigene Arbeit selbst | git-**Author** = die Identität (`GIT_AUTHOR_*`), Claude-Trailer aus (`attribution.commit:""`) | Agent in der **Author**-Spalte |
| **Delegiert** — Bob (o.ä.) committet Code, den ein anderer Bob baute | git-Author = der **committende** Bob; der **ausführende** Bob als `Co-Authored-By:`-Trailer im selben Persona-Format | Committer = Author, Macher = **Co-Author** |

In BEIDEN Fällen ist das Identitäts-Format identisch: `<Name> (<Projekt-Display> <role>) <DEV_TEAM_EMAIL>`.
Der `Co-Authored-By:`-Trailer ersetzt den alten Claude-Trailer (`Claude … <noreply@anthropic.com>` → raus).

`git-identity.sh` deckt beide ab über `COMMIT_IDENTITY_MODE`:

| Modus | Verhalten |
|---|---|
| `author` *(Default — Solo-Commit)* | setzt `GIT_AUTHOR_*`/`GIT_COMMITTER_*` auf die eigene Identität |
| `trailer` | gibt `Co-Authored-By: <Identität>` aus → bei Delegation an die Commit-Message hängen (für den ausführenden Bob) |
| `both` | Author = eigene Identität **und** ein zusätzlicher Co-Author-Trailer |

**Praktisch:** Eine Solo-Session exportiert `git-identity.sh export` (Modus `author`). Committet **Bob**
fremde Arbeit, generiert er den Co-Author-Trailer des Machers via `COMMIT_IDENTITY_MODE=trailer
HEARTBEAT_AGENT=<Macher> git-identity.sh trailer` und hängt ihn an die Message. Idealerweise
automatisiert über `onboard`-Attribution statt manuell getippt.

## Auflösung (im Script)

```
ID-Key   THEME_AGENT_ID  (z.B. BOB-dashboard)  →  sonst reverse-lookup per HEARTBEAT_AGENT (Name)
NAME     theme.json personas[ID].name
ROLE     theme.json personas[ID].positionLabel  →  sonst archetypes/<archetype>.positionLong  →  sonst leer
DISPLAY  dev-team.env PROJECT_NAME
EMAIL    dev-team.env DEV_TEAM_EMAIL  (Default team@litora-nova.com)
IDENT    "<NAME> (<DISPLAY> <ROLE>) <EMAIL>"   bzw. ohne ROLE: "<NAME> (<DISPLAY>) <EMAIL>"
```

- **ID-Key-Resolution:** Primär `THEME_AGENT_ID` (exakt, kollisionsfrei). Fallback = reverse-lookup
  über `HEARTBEAT_AGENT` (der Name, den der Heartbeat-Hook ohnehin setzt) → finde die Persona, deren
  `name` matcht. Ist der Name in mehreren Personas (sollte nicht vorkommen), gewinnt der erste Treffer
  + Warnung auf stderr.
- **i18n-`positionLabel`:** Ist `positionLabel` ein `{de,en}`-Objekt, nimmt das Script die `en`-Variante
  (Commit-Messages sind projektweit englisch-neutral; `DEV_TEAM_LOCALE` kann das überschreiben).

## So nutzt du es

- **In einer Agent-Session (per-Session-Env, wie `HEARTBEAT_AGENT`):**
  ```bash
  eval "$(scripts/git-identity.sh export)"   # exportiert GIT_AUTHOR_* / GIT_COMMITTER_* (Modus author)
  ```
  Danach trägt jeder `git commit` die Agenten-Identität. Wird typischerweise vom SessionStart-Hook
  bzw. `bin/onboard` Baustein 4 verdrahtet (parallel zu `session-heartbeat`).
- **Trailer-Modus** (falls der PO so entscheidet):
  ```bash
  COMMIT_IDENTITY_MODE=trailer scripts/git-identity.sh trailer   # gibt die Co-Authored-By-Zeile aus
  ```
  → in eine `commit.template` oder einen `prepare-commit-msg`-Hook hängen.
- **Einzelwert abfragen:** `scripts/git-identity.sh print` (gibt die volle Identität als eine Zeile).

## Wire-in (onboard Baustein 4)

`bin/onboard` Baustein 4 (Hook-Install) verdrahtet `git-identity.sh` analog zum Heartbeat: ein
Projekt-Wrapper-Hook, der bei SessionStart `eval "$(scripts/git-identity.sh export)"` ausführt.
Die scharfe settings.json-Verdrahtung ({HUMAN}-OK) bleibt **Stufe C** — onboard schreibt nur den
Wrapper, hängt ihn NICHT selbst in settings.json.

## Sprache (PO 2026-07-17)

**Alles Öffentliche ist Englisch:** Commit-Messages, Issues, PRs und Release-Notes — alles, was
in public Repos oder öffentlichen Trackern landet — wird auf Englisch verfasst, unabhängig von
der Team-Sprache. Interne Artefakte (Inbox, Heartbeats, Audits, Continuity-/Standup-Notizen,
private Repos) bleiben in der Team-Sprache. (Passend dazu nutzt die `positionLabel`-i18n-Auflösung
oben bereits die `en`-Variante.)

## Harte Regeln

- **Daten vor Code:** Name/Rolle/Display/Email kommen aus `theme.json`/`dev-team.env`, NIE aus dem
  Script-Body. Eine neue Regel = diese `.md` + die Daten editieren, nicht das Script patchen.
- **Kein statisches `user.name`/`user.email` im Repo** setzen (das war der Mario-Bug:
  `Claude-tools/.git/config` stand statisch auf `Mario` → JEDER Commit war Mario). Identität ist
  **per-Session-Env**, nicht repo-global.
- **Fail-safe:** Fehlt `theme.json`/`dev-team.env` oder ist ein Feld leer, gibt das Script eine klare
  Warnung auf stderr und (im `export`-Modus) NICHTS aus, statt eine kaputte Identität zu setzen —
  dann gilt der git-Default (besser als ein Commit mit `() <>`-Müll).
- **Geteilte Email:** Distinkte Namen, gleicher Avatar (eine Email → ein GitHub/GitLab-Avatar). Das ist
  gewollt (Setup-arm); per-Agent-Avatare wären per-Agent-Emails = mehr Setup, bewusst NICHT gemacht.

## Client-seitiger Floor (Issue #59)

Der `Mario-Bug` oben (statisches `user.name` im Repo) und ein späterer Fund (eine private
Mail-Adresse landete als Commit-Autor in einem öffentlichen Repo, erst NACH dem Push von der
Compliance-Gate gefangen) zeigen: diese Doku allein verhindert eine falsche Identität nicht,
sie erklärt nur, wie es richtig geht. `hooks/pre-push-identity-floor.sh` (Registry:
`team-rules/hooks.md`) prüft AUTOMATISCH vor jedem `git push`, ob Autor/Committer dem Kanon-
Format oben entsprechen — client-seitig, VOR dem Push, opt-in via `bin/onboard`. Es ist ein
Floor/Frühwarnsystem, kein Ersatz für die Compliance-Gate-Beurteilung (die sieht mehr als ein
Client-Hook je kann) — dokumentierter Bypass: `BOBNET_PUSH_FLOOR_SKIP=1 git push`.
