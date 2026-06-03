# CONVENTIONS — claude-dev-team (harte Regeln)

Verbindliche Regeln für das Team-OS. Gelten projekt- und themen-übergreifend.

## 1. Beschreibende Namen & IDs — NIEMALS opak (HARTE Regel, Austin 2026-06-02)

> **Jeder Agent, Bob und externe Coworker — und der Mensch — bekommt IMMER einen
> beschreibenden, rollen-basierten Namen UND eine stabile beschreibende `id`.**
> Auch in der *internen* Kommunikation (Heartbeats, @-Mentions, Logs, Task-Owner, Inbox).
> **Verboten:** generische/opake Tokens wie `agent1`, `agent2`, `p0`, `u1`, `bot3`.

- **Bob = `team_lead`/`techlead`**, nicht `agent1`. **Der Mensch = `human`**, nicht `p0`.
- **Warum:** Eindeutige, sprechende Namen haben in der Praxis viele Koordinations-Probleme
  *verhindert* — ohne sie „klappt die Teamarbeit nicht mehr" (Austin). Opake IDs erzeugen
  Verwechslung, Fehl-Zuordnung von Tasks, kaputte @-Mentions.
- **`id`-Schema** (stabil, aufgabenbasiert, **themen-unabhängig**): `<KATEGORIE>-<rolle>`
  — `BOB-techlead`, `BOB-backend`, `BOB-review`, `EXT-design`, `SVC-guppi`, `HUMAN-bob`.
  Kategorie aus der Taxonomie (`bob`/`service`/`coworker`/`helper`/`human`), Rolle = der
  beschreibende Archetyp-Slug. Die `id` ändert sich NIE (Branches/Logs/Refs hängen dran);
  der **Name** ist nur Anzeige und kommt aus dem Theme.
- **Quelle/Kanon der konkreten IDs:** `acme-bobiverse/docs/BOB_MATRIX.md` bzw. die
  `team.config.json` der Instanz. Neue Rollen → neue beschreibende id, kein Durchnummerieren.
- **In Logs/Heartbeats/Tasks** immer den Namen ODER die id verwenden, nie einen generischen Platzhalter.

### 1a. Zwei id-Ebenen — Archetyp-id vs. Spawn-UID (Plan §9)

Es gibt **zwei komplementäre Identitäts-Ebenen**, die NICHT verwechselt werden dürfen:

| Ebene | Schema | Beispiel | Scope | Quelle |
|---|---|---|---|---|
| **Archetyp-/Persona-id** | `<KATEGORIE>-<rolle>` | `BOB-backend` | themen-/projekt-**un**abhängig; bindet Archetyp ↔ Theme-Persona | `idPattern` im Archetyp, `team.config.json` |
| **Spawn-UID** (Instanz) | `<PROJECT_UID>-<role>` | `acme-backend-dev` | **eine** konkrete Agent-Instanz in **einem** Projekt-Bobiverse | `dev-team.env` → `PROJECT_UID` + Archetyp-Tags/Rolle |

- **Warum projekt-präfixiert:** im BobNet (das mehrere Projekt-Bobiverses sieht) macht der
  `<PROJECT_UID>-`-Prefix sofort klar, **wessen** Backend-Bob es ist (`acme-backend-dev` vs.
  `keyhub-backend-dev`). Cross-Team-Comms via SCUT adressieren über diese UID.
- **`PROJECT_UID` ist immutabel** (kurzer Namespace, z.B. `acme`) — der Display-Name darf wechseln
  (`Acme Inc`), die UID nie. Sie wird beim Onboarding einmal abgefragt (`dev-team.env`).
- **Angewandt wird die Spawn-UID** beim Spawn durch `init-bobs`/Bob#1 (Agent-`id` der Instanz),
  in Heartbeat-/Log-Routing und als SCUT-Adress-Token (`[uid]` in der Routing-Tabelle).
- **Dashboard-Ausblendung:** das BobNet schneidet den `<PROJECT_UID>-`-Prefix für die *Anzeige* ab
  (zeigt „Backend"), behält die volle UID intern (kollisionsfrei). Das Bauen dieser Ausblendung ist
  Garfields Revier (`dashboard`-Tag) — hier nur benannt, nicht implementiert.

## 2. Avatar / Anzeige (HARTE Regel — siehe `themes/`)

- **Team-Mitglieder werden im BobNet AUSSCHLIESSLICH als Bild angezeigt — NIE als Emoji**,
  auch nicht als Fallback/Option. Wer Emoji-Faces will, baut sein eigenes Theme.
- **Jedes Theme MUSS ein `defaultAvatar` (Bild) haben** (`themes/<id>/avatars/default.png`,
  erst die Anonymous-/Hacker-Maske, austauschbar). Fehlt einer Persona ein Avatar → defaultAvatar.
- **Theme-Settings** (`theme.json` → `settings`, erweiterbar): z. B. `showAvatars` (Bild ja/nein;
  bei `false` nur der Name — nie ein Emoji).

## 3. Style / Look-&-Feel

- **Sichtbare Defaults/Fallbacks (Avatare, Farben, Layout-Feel) vorher mit dem PO abstimmen** —
  nicht eigenmächtig setzen.

## 4. State / Sync

- **Sync = Git** (`fetch`+`pull`+`push` gegen `origin`). `origin` = die eine Wahrheit; Maschinen
  syncen *über* origin, nicht als direkte Maschinen-Achse. **Push gehört zum Sync** — committen reicht nicht.
