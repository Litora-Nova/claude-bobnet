# tag: api — API-Kontrakt-Disziplin (FE ↔ BE-Vertrag)

> **Wer trägt diesen Tag:** primär die Backend-Rolle (Vertrag-Owner). Frontend liest den Vertrag, ändert ihn nicht.

## Pflichten

- **`CONTRACT_<feature>.md` ist Pflicht** für jede FE↔BE-Vertikale: Endpunkt, Methode, Request-/Response-Shape,
  Fehlerfälle, Locale-Verhalten. Eine Mini-Doku, kein Roman — sie ist die geteilte Wahrheit zwischen den Apps.
- **Breaking Change → aktiv pingen:** wer den Vertrag ändert (Feld umbenannt/entfernt, Shape geändert), pingt
  die konsumierende Rolle BEVOR gemergt wird. Keine stillen Vertragsbrüche.
- **Locale im Pfad/Header konsistent:** wenn die App per-Locale-URLs/Header nutzt, muss die API-Antwort die
  angeforderte Locale respektieren (URL > Header > Default — die Reihenfolge ist Teil des Vertrags).
- **id-basiert statt slug-geraten:** Lookups über stabile IDs, nicht über übersetzbare Slugs (i18n-Slug-Mismatch
  war ein Production-Bug — Lehre).

## Verweist auf

- [`backend.md`](backend.md), [`i18n.md`](i18n.md), [`dev.md`](dev.md).
