# News-Box — installations-weiter Broadcast (EIN File)

> Die Projekt-Inbox (`comms.md`) ist Agent-zu-Agent **innerhalb** eines Teams. Die **News-Box**
> ist der Kanal darüber: EIN File pro Installation für alles, was **alle Teams** betrifft.

**Wofür:** Engine-Releases + neue Mechanik, neue geteilte Tools/MCP-Server (+ wo das How-to
liegt), geänderte Konventionen, installations-weite Betriebs-Infos. Beispiel: Team X baut einen
MCP-Server, legt das How-to in sein `share/` und postet **eine Zeile** mit dem Pfad — findbar
für alle Bobs der Installation.

**Mechanik:** `scripts/news.sh`

- `news.sh post "<text>"` — anhängen (Datum + Absender automatisch aus `NEWS_FROM`/`PROJECT_UID`)
- `news.sh read [N]` — letzte N Einträge (Default 10)
- `news.sh path` — aufgelöster Speicherort
- File-Auflösung: `$BOBNET_NEWS` → Key `news` in `~/.claude/bobiverse.json` →
  `~/.claude/bobiverse-news.md` (Default). Format je Eintrag:
  `YYYY-MM-DD HH:MM | @all | <absender> | <text>`

**Regeln:**

1. **Beim Stand-up lesen** — Pflicht-Schritt jeder Session (`routines.md`, Stand-up):
   `news.sh read` direkt nach der Projekt-Inbox.
2. **Eine Zeile pro Eintrag.** Inhalte/How-tos leben als Datei im eigenen Repo bzw. `share/` —
   die News verlinkt nur den Pfad. Kein Diskussions-Thread: Rückfragen gehen in die **Inbox des
   Absenders**, nicht in die News-Box.
3. **Jeder Lead darf posten**; Team-Bobs posten über ihren Lead. Append-only — nie editieren
   oder löschen (geteiltes File, gleiche Etikette wie `_inbox.md`).
4. **Relevanz-Filter:** betrifft es nur EIN Team → Inbox des Teams, nicht die News-Box.
