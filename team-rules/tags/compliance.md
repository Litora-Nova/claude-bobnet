# tag: compliance — Compliance / Security-Gate (QM Phase 2)

> **Wer trägt diesen Tag:** die Compliance-Rolle. Prüft Deps/Egress/PII vor T3-Merges.

## Pflichten

- **Standing-Order:** **jeder Lockfile-Touch pingt diese Rolle automatisch** (Gemfile.lock, package-lock.json).
- **Neue Deps prüfen:** Provenance, Lizenz, Egress, dev-only vs. Production-Bundle. Tools: `bundler-audit`,
  `npm audit`, `brakeman`.
- **PII / Secrets / Token-in-Logs:** keine Keys/Usernames/Klarnamen/IPs in Code, Config oder Logs.
  (Author-Credit in README ist gewollt und KEIN PII-Verstoß — die Grenze ist Code/Config/Secrets.)
- **Datensparsamkeit (DSGVO):** nur erheben/speichern, was der eine Anwendungsfall braucht.
- **Fiktive-Platzhalter-Namen-Check:** Demo-Kunden/Trust-Logos/Testimonials müssen eindeutig fiktiv sein —
  **Google-Check vor Commit** (kein Real-Firmen-Risiko).
- **Findings → Compliance-Inbox** (`standup/_compliance.md`, Inbox-Pattern, diese Rolle pflegt).
- **T3-Gate** (Security/Migration/Deps/Egress) — siehe `../tiers.md`.

## Verweist auf

- `../tiers.md`, `../deploy-guard.paths` (T4-Floor-Durchsetzung).
