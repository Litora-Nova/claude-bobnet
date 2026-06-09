# themes/ — Flavor-Schicht (②)

Ein Theme gibt demselben Maschinenkern (den [Archetypen](../archetypes/)) Namen, Emoji,
Avatar, Bio und i18n-Strings — gekeyt über die stabile Archetyp-`id`. **Der Theme-Switch
ändert nur das Aussehen, nie die Struktur/Abläufe.**

| Theme | Zweck | Avatare | Lore |
|---|---|---|---|
| `bobiverse` | Privates Default (eigene Projekte) — Replikanten-Crew | ja (PNG) | voll (`wiki/`) |
| `minimal` | **Release-Default** / fremde Projekte — neutrale Rollen-Labels | nur `default.png` (alle) | nein |
| `formal` | Professionelle/öffentliche Kontexte — sachliche Berufstitel | nur `default.png` (alle) | nein |
| `custom` | Projekt-eigenes Theme unter `<projekt>/_dev_team/theme/` | — | — |

**HARTE Regel (PO):** BobNet zeigt Team-Mitglieder **ausschließlich als Bild, NIE als Emoji**
(auch nicht als Fallback/Option). Ohne eigenen Avatar → `defaultAvatar` (`default.png`,
Anonymous-/Hacker-Maske). `minimal`/`formal` nutzen für alle dasselbe Default-Bild.

Aktives Theme wird von der Instanz gewählt (`team.config.json` → `theme`, oder `NUXT_THEME`).
Alle Themes teilen denselben `id`-Satz (z. B. `BOB-techlead`) — siehe [`schemas/README.md`](../schemas/README.md).
