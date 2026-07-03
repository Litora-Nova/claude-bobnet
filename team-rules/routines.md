# team-rules/routines.md — Session-Start & Session-Ende (Engine-Canon)

> Die zwei Spiegel-Routinen, die einen Arbeitstag rahmen. Generischer Kern — Projekt-Details
> (welche Repos, welche Docs) kommen aus `dev-team.env` + dem Projekt-Override.
> Tokens: `{TEAM_LEAD}` = Projekt-Lead, `{HUMAN}` = Product Owner.
> Projekt-Override: gleichnamiges File unter `_dev_team/team-rules/routines.md` (Engine = Fallback).

## Session-Start (Trigger: „stand-up" / „sprint" / „Team wecken" / sinngemäß)

> Bei Unklarheit (nur „los"/„weiter"): `{TEAM_LEAD}` fragt explizit „Team-Start oder Einzelauftrag?".

1. **Sync zuerst** — `fetch` → `pull` → `push` über alle Repos + Branch-Check (siehe `sync.md`).
   Fester erster Schritt vor allem anderen.
2. **Team aktiv + Heartbeat** — jedes aktive Team-Mitglied klinkt sich mit einem ersten,
   status-bezogenen Heartbeat ins BobNet ein (siehe `heartbeat.md`). Kein prophylaktisches
   „ich-bin-da"-Spammen. **Dabei die Inbox lesen** (`<standup>/_inbox.md`) — sie ist der
   Default-Kanal für Agent-zu-Agent-Nachrichten (siehe `comms.md`) — **und danach die
   News-Box** (`scripts/news.sh read`): installations-weite Updates aller Teams
   (Engine-Releases, neue shared Tools/MCPs — siehe `news.md`).
3. **Operations-Modus fragen** — `{TEAM_LEAD}` fragt den `{HUMAN}` *einmal*:
   - **Autonomie-Modus** (Default): `{TEAM_LEAD}` entscheidet eigenständig, Staging-Autonomy aktiv
     (siehe `autonomy.md`). Für normale Sprint-Tage.
   - **Plan-Modus** (Drift-sicher): `{TEAM_LEAD}` bleibt im Planmodus, ein **hiwi**-Executor führt
     eine nummerierte `PLAN_*.md` strikt aus (siehe `tags/hiwi.md`). Für riskante Sprints
     (Migration, Datenmodell-Umbau, großer Architektur-Pivot).
   - Der gewählte Modus gilt für den Tag — nicht nach jedem Schritt neu erfragen.
4. **Sprint-Plan konsolidieren** — auf Basis des letzten Abschluss-Docs + der `{HUMAN}`-Antworten.
   Bei größeren Vorhaben gilt **roadmap-first**: erst Plan/Roadmap schreiben + speichern, dann bauen.

## Session-Ende (Trigger: „Feierabend" / „Schluss für heute" / sinngemäß)

> Spiegel zum Start. Läuft, BEVOR die letzte Antwort gesendet wird. Ziel: nichts halb-committed,
> halb-gepingt, halb-dokumentiert — der nächste Tag startet mit Arbeit, nicht Aufräumen.

1. **Laufende Agents abwarten oder bewusst parken** — keine Background-Tasks in Limbo;
   Halb-Fertiges dokumentieren.
2. **Offene Branches mergen oder parken** — Gate-GRÜNE Branches mergen, sonst explizit als
   „wartet auf morgen" + Begründung markieren.
3. **Alles committen + pushen** — `git status` sauber; besonders `_dev_team/` + `standup/` (wird
   chronisch vergessen). Committen reicht nicht — Push gehört dazu (siehe `sync.md`).
4. **Memory / Docs sichern** — neue Patterns/Regeln ablegen, Doc-Drift gegen Code einpflegen.
5. **Docs-Rolle nachziehen (Trigger `feierabend`)** — die docs-Rolle (Archetyp `docs`) MUSS bei
   jedem Feierabend die Dokumentation für das am Tag Geshippte aktualisieren. Pflicht-Schritt,
   kein Optional: `triggers: ["feierabend"]` macht diesen Lauf verpflichtend.
6. **Abschluss-Doc schreiben** — Tagesbilanz, Morgen-Sequenz, offene `{HUMAN}`-Items, neue Routinen.
   Es ist der Anknüpfungspunkt für den nächsten Session-Start.
7. **Team auf idle** — alle aktiven Mitglieder explizit auf `idle` heartbeaten.
8. **Tasks aufräumen** — keine stalen `in_progress` über Nacht; offene Items klar markieren,
   erledigte `{HUMAN}`-Tasks abhaken.

## Harte Regeln

- **Ausnahme „Feierabend ABER fix noch X":** X ist die letzte Aktion VOR der Routine, nicht parallel.
- **„Pause"/„kurz weg" ≠ Feierabend** — nur Idle-Heartbeat + Standby, keine volle Routine.
- Daten vor Code: welche Repos/Docs konkret kommen aus `dev-team.env` + Projekt-Override, nicht hierher.
