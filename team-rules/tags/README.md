# team-rules/tags/ — Geteilte Anweisungen pro Tag (Daten vor Code)

> Jeder Archetyp trägt ein `tags[]`-Array (z.B. backend `{backend, dev, db, api}`).
> Die **gemeinsamen** Pflichten/Patterns eines Tags stehen **einmal** in `<tag>.md` — nicht
> dupliziert pro Agent. Der Agent-Init lädt seine Rolle (Archetyp) **+ die `.md` zu jedem seiner Tags**.
> So bekommt jeder Agent nur den Kontext, den er braucht (Plan §9).

## Wie es zusammenspielt

```
Archetyp (archetypes/<role>.json) ──tags[]──▶ team-rules/tags/<tag>.md  (geteilte Anweisung)
                                  ──duties[]─▶ rollen-spezifische Pflichten (referenzieren Tags)
```

- **Tag = geteilte Mechanik** (gilt für ALLE Rollen mit dem Tag).
- **duties[] = rollen-spezifisch** (was nur diese eine Rolle tut) — sie verweisen auf die Tags
  statt deren Inhalt zu duplizieren.
- **Override-Kette** (wie alle team-rules): Projekt `_dev_team/team-rules/tags/<tag>.md` **>**
  BobNet House-Rules **>** diese Engine-Defaults.

## Der `dev`-Trigger (konditionale Pflichten)

`dev` ist der **Bauer-Marker**. Trägt eine Rolle `dev`, gelten automatisch **TDD-Pflicht +
Kommentare-schreiben** (siehe [`dev.md`](dev.md)). Das ist die Mechanik hinter der Plan-Regel
„Pflichten jeder Bob: … TDD (wenn dev) · Kommentare schreiben (wenn dev)". QM-/Service-Rollen
ohne `dev` bauen keinen Produkt-Code und tragen den Tag daher nicht.

## Tag-Taxonomie (Stand Phase C)

| Tag | Klasse | Was es trägt | Rollen (Beispiel) |
|---|---|---|---|
| `dev` | Pflicht-Marker | TDD + Kommentare (konditional, s.o.) | backend, frontend, website, content, hiwi |
| `hiwi` | Prozess | Plan-Executor-Protokoll (strikte nummerierte PLAN-Ausführung, Drift=STOP, 3-Sektion-Report) | hiwi |
| `backend` | Area | Rails-/JSON-API-Mechanik, Kontrakte, FSM | backend |
| `frontend` | Area | Component-/Composable-/Client-Mechanik | frontend |
| `website` | Area | Marketing-Site / statische Generierung | website |
| `db` | Area | Migrations, Seeds, Schema-Disziplin | backend |
| `api` | Area | API-Kontrakt-Disziplin (FE↔BE-Vertrag) | backend (frontend liest) |
| `js` | Area | JS/TS-/Nuxt-Mechanik | frontend, website |
| `i18n` | Querschnitt | beide Locales, Parität, URL↔Locale | frontend, website, content |
| `seo` | Querschnitt | title/description/useSeo, OG | website |
| `review` | QM | Code-Review-Gate (T1–T3) | review |
| `compliance` | QM | Deps/Egress/PII/Secrets | compliance |
| `tests` | QM | Coverage-Floor, Behavior>Pattern | tests |
| `release` | QM | Pre-Flight, Deploy-Owner | release |
| `docs` | Querschnitt | Doku-Pflicht, Doc-Drift | docs (alle bei Bedarf) |
| `content` | Area | Lektionen/Texte, kein Lösungs-Leak | content |
| `dashboard` | Service | Read-only standup, eigene Heartbeat-Datei | dashboard |
| `ops` | Service | Prozess-/Schedule-Überwachung, Eskalation | guppi |
| `process` | QM | Meta-Kontrolle: liefen die Gates? | process-auditor |

Neue Rolle → passende Tags vergeben (oder neuen Tag + `<tag>.md` anlegen). Kein Code-Touch nötig.
