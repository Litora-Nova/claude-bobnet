# team-rules/heartbeat.md — Heartbeat-Routing (beschreibende Regel)

> Diese Datei ist die **Daten-/Regel-Quelle** für `hooks/session-heartbeat.sh`. Der Hook liest
> `HEARTBEAT_AGENT` (Env) + `TEAM_LEAD` + `STANDUP_DIR` aus `dev-team.env` und schreibt einen
> SessionStart-Heartbeat. **Routing-Regel ändern = hier (Daten) editieren, nicht im Script.**
> Projekt-Override: gleichnamiges File unter `_dev_team/team-rules/heartbeat.md` (Engine = Fallback).

## Kanon
- **Jede Session, die mit einer Instanz zusammenarbeitet, heartbeatet als _ihr_ Agent in _deren_
  `STANDUP_DIR`** (= deren BobNet). Das Dashboard der kollaborierenden Instanz sieht damit sofort,
  WER online ist und WO mitgearbeitet wird.
- **Lead-Session:** `HEARTBEAT_AGENT` **unset** → Default `$TEAM_LEAD`. So bleibt es für ein
  normales Projekt rückwärtskompatibel (kein Bruch — der Lead heartbeatet als er selbst ins
  eigene BobNet).
- **Cross-project shared Services** (Garfield/GUPPI — ein Service, der in JEDES Team-BobNet pingt,
  nicht nur als Lead): setzen **`HEARTBEAT_AGENT=<Name>`** + **`STANDUP_DIR=<Kollab-Instanz>`**.
  So loggt z.B. Garfield als `Garfield` ins BobNet des Projekts, das er gerade bedient — statt
  fälschlich als dessen Lead.

## Auflösung (im Hook)
```
AGENT = HEARTBEAT_AGENT  (gesetzt)  →  sonst  TEAM_LEAD  (sonst Fallback "Bob")
ZIEL  = STANDUP_DIR      (aus dev-team.env; log.sh schreibt <STANDUP_DIR>/<AGENT>.log)
```

## So nutzt du es
- **Normales Projekt (Lead-Heartbeat):** nichts tun. `dev-team.env` setzt `TEAM_LEAD` + `STANDUP_DIR`,
  der Hook heartbeatet automatisch als Lead ins Projekt-BobNet.
- **Shared Service in fremdem BobNet:** vor der kollaborierenden Session zwei Env-Variablen setzen —
  ```bash
  export HEARTBEAT_AGENT="Garfield"
  export STANDUP_DIR="/pfad/zur/kollab-instanz/_dev_team/standup"
  ```
  Dann startet die Session: der SessionStart-Hook schreibt `Garfield busy session-start` in das
  BobNet der Kollab-Instanz. Manuell prüfbar:
  ```bash
  HEARTBEAT_AGENT=Garfield STANDUP_DIR=/tmp/demo/standup hooks/session-heartbeat.sh
  # → /tmp/demo/standup/Garfield.log enthält "... | busy | session-start"
  ```

## Harte Regeln
- **Fail-safe:** Der Hook blockt die Session NIE — fehlt `log.sh` oder schlägt es fehl, still `exit 0`.
- **Default nie hart auf einen Namen:** Default ist `$TEAM_LEAD` (projekt-definiert), nicht ein
  fest verdrahteter Name. Ein leeres `TEAM_LEAD` fällt nur als letzte Reserve auf `Bob` zurück.
- **Daten vor Code:** Agent + Ziel kommen aus Env/`dev-team.env`, nie aus dem Script-Body.
