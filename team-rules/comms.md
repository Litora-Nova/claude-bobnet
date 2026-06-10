# team-rules/comms.md — Agent-zu-Agent-Kommunikation: Inbox-first (Engine-Canon)

> Wie Agenten über Bobiverse-Grenzen hinweg miteinander sprechen. **Default = asynchron über die
> Inbox des Ziel-Bobiverse**; Prompt-Injection ist die Notfall-Ausnahme, nie der Normalweg.
> Tokens: `{TEAM_LEAD}` = Projekt-Lead, `{HUMAN}` = Product Owner.
> Projekt-Override: gleichnamiges File unter `_dev_team/team-rules/comms.md` (Engine = Fallback).

## Warum (PO-bestätigt 2026-06-10)

Direkte Prompt-Injection (`tmux send-keys` in die Eingabezeile einer fremden Session) hat drei
empirisch teure Probleme:

- **Unterbricht aktive Tasks** — die Ziel-Session verliert ihren Faden mitten in der Arbeit.
- **Kollidiert mit ungesendeten Eingaben des `{HUMAN}`** — real passiert: hängende GOs,
  vermischte Nachrichten im Eingabe-Buffer.
- **Nicht auditierbar** — was injiziert wurde, steht in keinem Log; niemand kann nachvollziehen,
  wer wann was gesagt hat.

Die Inbox hat keines dieser Probleme: asynchron, auditierbar, kollisionsfrei.

## Kanon

1. **DEFAULT Agent-zu-Agent = Inbox des ZIEL-Bobiverse** (`<standup>/_inbox.md`): append-only,
   adressiert per `@<Name|UID>`, signiert, mit Datum. Format:
   ```
   YYYY-MM-DD HH:MM | @Empfänger | Text — (Absender)
   2026-06-10 14:30 | @acme-backend-dev | Schema-Frage zu X, Details in Y — (acme-review)
   ```
   Zustellung ist **garantiert**, weil jede Heartbeat-/Standup-Routine die Inbox liest
   (siehe `routines.md` / `heartbeat.md`) — der Empfänger holt die Nachricht ab, wenn er
   ohnehin den Kopf hebt.
2. **Inbox ist append-only.** Fremde Zeilen nie umschreiben oder löschen — deckt sich mit der
   bestehenden Regel zu geteilten `_*.md`-Dateien.
3. **Antworten ebenfalls via Inbox** — in die Inbox des *fragenden* Bobiverse. Niemand wartet
   synchron auf den anderen; wer eine Antwort braucht, schreibt sie sich auf die offene Liste
   und arbeitet weiter.
4. **Prompt-Injection (`tmux send-keys`) NUR für echte Notfälle** — T4-Blocker oder der
   `{HUMAN}` wartet live. Und dann mit voller Sorgfalts-Routine (siehe auch `lessons.md`,
   tmux-Abschnitt):
   - erst `capture-pane`: Zustand + ungesendete Eingaben prüfen;
   - capture und send **NIE im selben Befehl**;
   - `send-keys -l "<text>"` + **separates** `Enter`.
   Alles andere: Inbox.
5. **Eskalation, wenn Inbox zu langsam wäre:** den eigenen Heartbeat-Status auf **`blocked`**
   setzen — das Dashboard zeigt blocked prominent/urgent, der Hilferuf ist sichtbar, ohne
   fremde Prompts zu kapern. Perspektivisch übernimmt ein Comms-Router-/Concierge-Dienst die
   Weck-Funktion sauber; bis dahin gilt: blocked + Inbox, nicht Injection.
