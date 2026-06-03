# tag: content — Kurs-/Produkt-Content

> **Wer trägt diesen Tag:** die Content-Rolle. Inhaltliche Arbeit (Lektionen, Texte, Showcase, Payloads).

## Pflichten

- **i18n-Parität aller Inhalte:** jede Lektion/jeder Text in beiden Locales, kein Hardcode (siehe [`i18n.md`](i18n.md)).
- **Keine Lösungs-Leaks in Payloads:** Question-/Quiz-Payloads dürfen die richtige Antwort nicht im Klartext
  ans Frontend liefern (Auswertung server-seitig).
- **Fiktive Platzhalter:** Demo-Kunden/Trust-Namen eindeutig fiktiv bis echte Stakeholder bestätigt sind
  (Google-Check, siehe [`compliance.md`](compliance.md)).
- **Datensparsamkeit + Auditierbarkeit** auch im Content (kein unnötiges PII in Beispielen).
- **Content folgt dem Vertrag:** Payload-Shapes kommen aus dem Backend-Kontrakt, nicht erfunden ([`api.md`](api.md)).

## Verweist auf

- [`i18n.md`](i18n.md), [`dev.md`](dev.md) (Content-Rolle trägt `dev` → Test/Doku-Pflicht für Content-Logik).
