#!/usr/bin/env bash
# tests/mux_spec.sh — Black-Box-Spec gegen den Multiplexer-Adapter
# scripts/lib/mux.sh (tmux | zellij). Prüft das in der Datei-Spec dokumentierte
# Verhalten: die Backend-WAHL (BOBNET_MUX=tmux|zellij|auto, ungültig = Fehler) und
# den Session-LIFECYCLE (mux_spawn/mux_has/mux_list/mux_kill) gegen das/die real
# verfügbare(n) Backend(s).
#
# CI-Portabilität: fehlt ein Backend-Binary, wird der betreffende Teil sauber
# GESKIPPT (kein hartes Fail) — auf der Dev-Box sind tmux UND zellij da, in fremder
# CI evtl. nur eins (oder keins). Das Gate darf dadurch NICHT rot werden.
#
# Hygiene: jede Test-Session trägt $$ im Namen (eindeutig) und wird nach jedem
# Lifecycle-Block wieder abgeräumt — diese Spec hinterlässt keine Sessions.
set -uo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/_helper.sh"

MUX="$SCRIPTS/lib/mux.sh"

it "mux.sh existiert"
ok test -f "$MUX"

# --- Backend-Verfügbarkeit (steuert WAS getestet wird) -----------------------
have_tmux=0; command -v tmux >/dev/null 2>&1 && have_tmux=1
have_zellij=0
if command -v zellij >/dev/null 2>&1 || [ -x "$HOME/.local/bin/zellij" ]; then have_zellij=1; fi

# mux_backend in einer Subshell mit gesetztem BOBNET_MUX auflösen (das Backend ist
# memoisiert — pro Probe daher EINE frische Subshell, sonst klebt der erste Wert).
backend_for() { ( export BOBNET_MUX="$1"; . "$MUX"; mux_backend ) 2>/dev/null; }
# Exit-Code der Auflösung (für die Fehlerfälle), STDERR unterdrückt.
backend_rc()  { ( export BOBNET_MUX="$1"; . "$MUX"; mux_backend >/dev/null 2>&1 ); }

# ── Backend-Wahl ──────────────────────────────────────────────────────────────
it "BOBNET_MUX=auto wählt tmux falls vorhanden (Rückwärtskompat), sonst zellij"
if [ "$have_tmux" = 1 ]; then
  eq "$(backend_for auto)" "tmux"
elif [ "$have_zellij" = 1 ]; then
  eq "$(backend_for auto)" "zellij"
else
  printf '  ⊘ SKIP: weder tmux noch zellij — auto nicht prüfbar\n'
fi

it "BOBNET_MUX=tmux erzwingt tmux (falls vorhanden)"
if [ "$have_tmux" = 1 ]; then
  eq "$(backend_for tmux)" "tmux"
else
  printf '  ⊘ SKIP: kein tmux installiert\n'
fi

it "BOBNET_MUX=zellij erzwingt zellij (falls vorhanden)"
if [ "$have_zellij" = 1 ]; then
  eq "$(backend_for zellij)" "zellij"
else
  printf '  ⊘ SKIP: kein zellij installiert\n'
fi

it "BOBNET_MUX=tmux ohne tmux => Fehler (rc!=0)"
if [ "$have_tmux" = 0 ]; then
  not_ok backend_rc tmux
else
  printf '  ⊘ SKIP: tmux IST da — Fehlerpfad nicht erzwingbar\n'
fi

it "BOBNET_MUX=zellij ohne zellij => Fehler (rc!=0)"
if [ "$have_zellij" = 0 ]; then
  not_ok backend_rc zellij
else
  printf '  ⊘ SKIP: zellij IST da — Fehlerpfad nicht erzwingbar\n'
fi

it "BOBNET_MUX=quatsch (ungültig) => Fehler (rc!=0)"
not_ok backend_rc quatsch

it "BOBNET_MUX=TMUX (Groß/Klein) ist NICHT gültig — Adapter matcht exakt klein"
# Doku-Spec: erlaubt sind exakt tmux|zellij|auto (lowercase). Alles andere = Fehler.
not_ok backend_rc TMUX

# ── Lifecycle gegen jedes real verfügbare Backend ─────────────────────────────
# Ein Verb gegen ein Backend in einer frischen Subshell (BOBNET_MUX gesetzt, mux.sh
# gesourct). Frische Subshell pro Aufruf, weil der Adapter das Backend memoisiert.
mux_call() { ( export BOBNET_MUX="$1"; shift; . "$MUX"; "$@" ); }

# Läuft mux_spawn -> mux_has -> mux_list -> mux_kill durch und räumt am Ende ab.
# Eindeutiger Session-Name mit $$ + Backend-Kürzel, damit parallele Läufe/Backends
# sich nicht ins Gehege kommen.
lifecycle() {
  local be name lst
  be="$1"
  name="muxspec_${be}_$$"
  # Sicherheitshalber etwaige Vorgänger (Name-Kollision bei Re-Run) entfernen.
  mux_call "$be" mux_kill "$name" >/dev/null 2>&1 || true

  it "[$be] mux_has vor mux_spawn => Session existiert NICHT (rc!=0)"
  not_ok mux_call "$be" mux_has "$name"

  it "[$be] mux_spawn legt eine (detached) Session an (rc==0)"
  ok mux_call "$be" mux_spawn "$name"
  # Settle-Pause: eine frisch gestartete zellij-Session ist ~1-2s lang noch nicht
  # voll registriert (delete-session --force läuft in dem Fenster ins Leere und
  # liefert "not found"/rc!=0, obwohl der Force-Kill greift). 2s machen den
  # Lifecycle für beide Backends deterministisch — und spiegeln die Realität, in
  # der Sessions ohnehin länger leben als Millisekunden.
  sleep 2

  it "[$be] mux_has nach mux_spawn => Session existiert (rc==0)"
  ok mux_call "$be" mux_has "$name"

  it "[$be] mux_list enthält die Session (eine pro Zeile)"
  lst="$(mux_call "$be" mux_list 2>/dev/null)"
  contains "$lst" "$name"

  it "[$be] mux_spawn ist idempotent (zweiter Aufruf rc==0, keine Doppel-Session)"
  ok mux_call "$be" mux_spawn "$name"

  it "[$be] mux_kill beendet die Session (rc==0)"
  ok mux_call "$be" mux_kill "$name"
  sleep 1

  # Das ist der eigentliche Kill-KONTRAKT (beobachtbares Verhalten, nicht der rc
  # des Kill-Verbs selbst): nach mux_kill ist die Session weg. Hält auch dann,
  # wenn ein Backend beim Kill einen eigenwilligen rc liefert.
  it "[$be] mux_has nach mux_kill => Session weg (rc!=0)"
  not_ok mux_call "$be" mux_has "$name"

  # Letzte Versicherung gegen Reste (z. B. wenn ein Assert oben kippte).
  mux_call "$be" mux_kill "$name" >/dev/null 2>&1 || true
}

if [ "$have_tmux" = 1 ]; then
  lifecycle tmux
else
  it "[tmux] Lifecycle"
  printf '  ⊘ SKIP: kein tmux installiert (CI-sicher grün)\n'
fi

if [ "$have_zellij" = 1 ]; then
  lifecycle zellij
else
  it "[zellij] Lifecycle"
  printf '  ⊘ SKIP: kein zellij installiert (CI-sicher grün)\n'
fi

summary
