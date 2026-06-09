# schemas/ — Struktur-Verträge

JSON-Schemas (draft-07) für die maschinenlesbaren Teile des Team-OS. Validieren
Archetypen, Themes und (später) `team.config` + Sprint-Lifecycle.

| Schema | Validiert | Schicht |
|---|---|---|
| `archetype.schema.json` | `archetypes/*.json` — *was* eine Rolle tut (universal) | ① Struktur |
| `theme.schema.json` | `themes/<id>/theme.json` — *wie* eine Rolle erscheint (Flavor) | ② Theme |
| `team.config.schema.json` | `<projekt>/_dev_team/standup/team.config.json` (Phase 3/4) | ③ Instanz |
| `registry.schema.json` | `projects.registry.json` — das Bobiverse-Zuständigkeits-Verzeichnis (Hub-Root, gitignored), konsumiert von Dashboard + Launcher (FR#7) | Hub |

## Join-Modell (die `id` ist der Dreh- und Angelpunkt)

```
Archetyp (techlead)  ──┐
                       │  team.config-Instanz wählt Archetyp + vergibt id (BOB-techlead)
Theme-Persona ─────────┴──►  id  ◄──── BOB-techlead → { name: "Bob", avatar: "Bob.png" }
(BOB-techlead)
```

> **HARTE Regel (Austin):** BobNet zeigt Team-Mitglieder **ausschließlich als Bild, NIE als Emoji**
> (auch nicht als Fallback/Option). Persona ohne Avatar → `defaultAvatar` (`default.png`).

- **`id`** (z. B. `BOB-techlead`) ist **stabil + aufgabenbasiert** — ein Member lässt sich
  umbenennen, ohne dass Branches/Logs/Referenzen brechen (`name` ist nur ein Theme-Feld).
- Ein **Archetyp** beschreibt die Mechanik (Ring, Gate-Tier, Model-Tier, Tools, Helfer-Klassen).
- Eine **Theme-Persona** hängt Flavor an dieselbe `id` (Name, Avatar/Default-Bild, Bio).
- Eine **Instanz** (`team.config`) sagt, *welche* ids aktiv sind, in welchem Revier, mit welchem
  Tier-Override und welchem Theme.

Validieren z. B. mit `ajv` oder `python -m jsonschema` (kein Runtime-Zwang — die Engine
liest die Files tolerant; Schemas sind Doku + CI-Gate).
