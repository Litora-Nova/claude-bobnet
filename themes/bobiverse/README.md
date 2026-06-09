# themes/bobiverse — Flavor: Replikanten-Crew (Schicht ②)

Privates Default-Theme für eigene Projekte. Mappt stabile Archetyp-`id`s auf
Lore-Bobs (Name/Emoji/Avatar/Bio). **Bobiverse ist nur EINES von mehreren Themes** —
Struktur/Abläufe ändern sich beim Theme-Switch nicht.

```
theme.json        id → { name, avatar, bio }  (validiert gegen schemas/theme.schema.json)
avatars/          <Name>.png (aus dashboard/public/avatars gespiegelt) + default.png (Fallback)
wiki/             bobiverse_background.md  — volle Lore/Stammbaum (Referenz)
strings/{de,en}   Flavor-Glossar (BobNet, ROAMER, Sonde, GUPPI, SCUT …)
members/          (optional) reichere Per-Member-Lore als <id>.md — derzeit ungenutzt (Bio in theme.json)
```

**HARTE Regel (PO):** BobNet zeigt Mitglieder **ausschließlich als Bild, NIE als Emoji** —
auch nicht als Fallback/Option. **Ohne eigenes Avatar-PNG** (Butterworth, GUPPI) kommt
`defaultAvatar` (`default.png`, Anonymous-/Hacker-Maske).
**Quelle der Persona-Daten:** `theme.json` (in diesem Repo). Der ausführliche Roster + das
Lore-Wiki bleiben **privat/lokal** (nicht im public Repo). *Schema = Tool (publizierbar), Wiki/Klarnamen = privat.*
