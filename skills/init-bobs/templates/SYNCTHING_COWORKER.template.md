<!--
  Coworker-Sync-Onboarding — kanonische Vorlage (white-label).
  Quelle/Goldstandard: von einem Projekt-Lead erprobt, in die Engine kanonisiert 2026-06-11.

  ZWECK: Ein externer Coworker (Designer, Marketing, …) auf einem {HUMAN}-Gerät dockt per
  Syncthing an den projekteigenen Bobiverse-Sync-Share an (siehe team-rules/comms.md §6).
  Diese Datei gehört in den `share/`-Ordner des Projekts — sie synct dann selbst zum Coworker.

  SO ANPASSEN (alle {{…}} ersetzen, dann diesen Kommentar löschen):
    {{PROJECT_DISPLAY}}    Anzeigename = Sync-Ordnername (= sync-share --name, z. B. "Acme Inc")
    {{SERVER_DEVICE_NAME}} Syncthing-Gerätename eures Servers (z. B. "acme-host")
    {{SERVER_DEVICE_ID}}   Geräte-ID eures Servers (Syncthing → Aktionen → ID anzeigen)
    {{DOCS_TARGET}}        Wohin gelieferte Templates final wandern (z. B. "acme_docs/templates/")
                           — Zeile streichen, falls das Projekt kein Doku-Repo hat.
  HINWEIS: Geräte-IDs sind nicht geheim (wie eine Telefonnummer), aber projekt-/infra-spezifisch
  — diese ausgefüllte Datei lebt nur im privaten share/, NICHT im public Engine-Repo.
-->
# {{PROJECT_DISPLAY}} ↔ Coworker — Syncthing-Anleitung

Hallo! 👋 Über diesen Sync-Ordner **„{{PROJECT_DISPLAY}}"** tauschen wir Assets aus —
direkt verschlüsselt von Gerät zu Gerät (Syncthing, kein Cloud-Dienst dazwischen).

**Was du siehst:** nur die Austausch-Bereiche (`_inbox/`, `share/`, `plan/`, `_inbox.md`).
Code, Repo-Interna und alles andere bleiben bei uns — das regelt eine Whitelist auf unserer Seite.

## Einrichtung (einmalig, ~10 Minuten)

1. **Syncthing installieren**
   - Mac: <https://syncthing.net/downloads/> → „Syncthing for macOS" (oder `brew install --cask syncthing`)
   - Windows: ebenfalls über die Downloads-Seite (z. B. „SyncTrayzor")
2. **Syncthing starten** — die Oberfläche öffnet sich im Browser unter `http://127.0.0.1:8384`
3. **Deine Geräte-ID kopieren:** oben rechts *Aktionen → ID anzeigen* → den langen Buchstaben-Block kopieren
4. **Geräte-ID an uns schicken** (Geräte-IDs sind nicht geheim — sie wirken wie eine Telefonnummer; verbinden kann sich nur, wen wir bestätigen)
5. **Warten auf unsere Freigabe:** wir fügen dein Gerät hinzu und teilen „{{PROJECT_DISPLAY}}" mit dir. Bei dir erscheinen dann nacheinander zwei blaue Banner in der Syncthing-Oberfläche:
   - *Neues Gerät „{{SERVER_DEVICE_NAME}}" möchte sich verbinden* → **Hinzufügen**
   - *Gerät {{SERVER_DEVICE_NAME}} möchte Ordner „{{PROJECT_DISPLAY}}" teilen* → **Hinzufügen**, Speicherort auf deinem Rechner frei wählen
6. Fertig — ab jetzt synct der Ordner automatisch, sobald beide Seiten online sind.

**Unser Server zum Gegen-Check** (falls Syncthing dich fragt):
Gerätename `{{SERVER_DEVICE_NAME}}`, ID `{{SERVER_DEVICE_ID}}`

## Ordner-Konventionen

| Ordner | Wofür |
|---|---|
| `_inbox/` | **Deine Anlieferung an uns:** fertige Assets (Logos, Bilder, Icons, Templates). Das Team holt sie hier ab und verschiebt sie ins Projekt (Templates landen final in {{DOCS_TARGET}}). |
| `share/` | **Austausch in beide Richtungen:** Briefings von uns an dich, Work-in-Progress, Feedback-Runden. |
| `plan/` | Planungs-Doku von uns — für dich zum Mitlesen. |
| `_inbox.md` | Kurznotizen, wenn es schnell gehen soll („Logo v3 liegt in _inbox, bitte Feedback"). |

## Format-Wünsche für Assets

- **SVG bevorzugt** für Logos/Icons; sonst **PNG mit transparentem Hintergrund**
- Bitte **keine JPGs für Logos** (kein Alpha-Kanal) und keine Messenger-Komprimierung — einfach die Originaldatei hier reinlegen, genau dafür ist der Ordner da 🙂
- Benennung gern sprechend: `logo-acme-dark-512.png` statt `final_v3_neu(2).png`

## Spielregeln

- Der Sync ist **bidirektional** — was du löschst oder umbenennst, ist auch bei uns weg. Bitte nur eigene Dateien anfassen.
- Konflikt-Dateien (`*.sync-conflict-*`) einfach liegen lassen und kurz Bescheid geben.
- Fragen / Freigaben: direkt an uns.

Danke dir — wir freuen uns auf die Zusammenarbeit! 🐻
