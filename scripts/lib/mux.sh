#!/usr/bin/env bash
# mux.sh — Terminal-Multiplexer-Adapter (tmux | zellij)
#
# Dünne, einheitliche Verben-Schicht, damit die Engine (Daemons, Dashboard-
# Activity, Comms) multiplexer-NEUTRAL bleibt: kein Skript ruft mehr `tmux`
# oder `zellij` direkt. Welcher Multiplexer benutzt wird, entscheidet EINE
# Stelle — die Env-Variable BOBNET_MUX.
#
# Nutzung (sourcen):
#   . "$(dirname "$0")/lib/mux.sh"
#   mux_spawn scut "STANDUP_DIR=~/standup scripts/scut-poll.sh"
#   mux_has  scut && echo "läuft"
#   mux_list                       # Session-Namen, einer pro Zeile
#   mux_send bob "[SCUT] hallo"    # Text + Enter (Notfall-Injection)
#   mux_capture bob                # sichtbarer Pane-Inhalt -> STDOUT
#   mux_kill scut
#
# Backend-Wahl (BOBNET_MUX):
#   tmux   -> immer tmux
#   zellij -> immer zellij
#   auto   -> (Default) tmux falls vorhanden (Rückwärtskompat), sonst zellij.
#             So flippt eine Bestands-Installation NICHT von selbst; der
#             Wechsel auf zellij ist eine bewusste Entscheidung (BOBNET_MUX=zellij,
#             z. B. bei der Erstinstallation abgefragt). Siehe README/onboard.
#
# Bekannte Backend-Unterschiede (wichtig für comms.md / scut-poll):
#   - zellij headless (Background-Session OHNE attached Client; empirisch 0.44.3, Issue #35):
#     `mux_spawn`/`run` LÄUFT (der Command startet) — aber `write-chars`/`write` erreichen
#     das Pane-stdin NICHT und `dump-screen` liefert leer, AUCH mit `--pane-id`. zellij
#     rendert/treibt ein Pane-Terminal nur mit Client; tmux adressiert detached Panes
#     server-seitig. → Boot geht headless, briefen/capturen NICHT. Darum: Inbox ist
#     Comms-Kanon (comms.md), Liveness via Heartbeat — Injection/capture nur Notfall.
#   - zellij liegt oft user-scope in ~/.local/bin (nicht im Cron-PATH) -> dieser
#     Adapter findet das Binary selbst (siehe _mux_bin).

# ---------------------------------------------------------------------------
# Backend + Binary auflösen (memoisiert)
# ---------------------------------------------------------------------------
_MUX_BACKEND=""
_MUX_BIN=""

_mux_have() { command -v "$1" >/dev/null 2>&1; }

# zellij auch finden, wenn es nur user-scope in ~/.local/bin liegt (Cron-PATH).
_mux_zellij_bin() {
  if _mux_have zellij; then command -v zellij; return 0; fi
  [ -x "$HOME/.local/bin/zellij" ] && { echo "$HOME/.local/bin/zellij"; return 0; }
  return 1
}

_mux_resolve() {
  [ -n "$_MUX_BACKEND" ] && return 0   # schon aufgelöst
  local want="${BOBNET_MUX:-auto}" zj
  zj="$(_mux_zellij_bin 2>/dev/null || true)"
  case "$want" in
    tmux)
      _mux_have tmux || { echo "mux: BOBNET_MUX=tmux, aber tmux nicht gefunden" >&2; return 1; }
      _MUX_BACKEND=tmux; _MUX_BIN="$(command -v tmux)" ;;
    zellij)
      [ -n "$zj" ] || { echo "mux: BOBNET_MUX=zellij, aber zellij nicht gefunden" >&2; return 1; }
      _MUX_BACKEND=zellij; _MUX_BIN="$zj" ;;
    auto)
      if _mux_have tmux; then _MUX_BACKEND=tmux; _MUX_BIN="$(command -v tmux)";
      elif [ -n "$zj" ]; then _MUX_BACKEND=zellij; _MUX_BIN="$zj";
      else echo "mux: weder tmux noch zellij gefunden" >&2; return 1; fi ;;
    *)
      echo "mux: ungültiges BOBNET_MUX='$want' (erlaubt: tmux|zellij|auto)" >&2; return 1 ;;
  esac
  return 0
}

# Öffentlich: welches Backend ist aktiv? (tmux|zellij)
mux_backend() { _mux_resolve || return 1; echo "$_MUX_BACKEND"; }

# ---------------------------------------------------------------------------
# Verben
# ---------------------------------------------------------------------------

# mux_spawn NAME [CMD...]
#   Startet eine DETACHED Session NAME. Ist CMD angegeben, läuft CMD darin.
#   Idempotent: existiert die Session schon, passiert nichts (exit 0).
mux_spawn() {
  _mux_resolve || return 1
  local name="$1"; shift || true
  [ -n "$name" ] || { echo "mux_spawn: Session-Name fehlt" >&2; return 2; }
  mux_has "$name" && return 0
  local cmd="$*"
  if [ "$_MUX_BACKEND" = tmux ]; then
    if [ -n "$cmd" ]; then "$_MUX_BIN" new-session -d -s "$name" "$cmd";
    else "$_MUX_BIN" new-session -d -s "$name"; fi
  else
    # zellij: detached Session anlegen, dann Command als Pane starten.
    "$_MUX_BIN" attach --create-background "$name" >/dev/null 2>&1 || true
    if [ -n "$cmd" ]; then
      "$_MUX_BIN" --session "$name" run -- bash -lc "$cmd" >/dev/null 2>&1 || return 1
    fi
  fi
}

# mux_has NAME -> exit 0 wenn Session existiert
mux_has() {
  _mux_resolve || return 1
  local name="$1"
  if [ "$_MUX_BACKEND" = tmux ]; then
    "$_MUX_BIN" has-session -t "$name" 2>/dev/null
  else
    "$_MUX_BIN" list-sessions --no-formatting --short 2>/dev/null | grep -qx -- "$name"
  fi
}

# mux_list -> Session-Namen, einer pro Zeile
mux_list() {
  _mux_resolve || return 1
  if [ "$_MUX_BACKEND" = tmux ]; then
    "$_MUX_BIN" list-sessions -F '#{session_name}' 2>/dev/null
  else
    "$_MUX_BIN" list-sessions --no-formatting --short 2>/dev/null
  fi
}

# mux_send NAME TEXT  -> Text + Enter in die Session (Notfall-Injection).
#   Achtung: bei zellij nur gegen Sessions mit Client zuverlässig (s. o.).
mux_send() {
  _mux_resolve || return 1
  local name="$1"; shift; local text="$*"
  if [ "$_MUX_BACKEND" = tmux ]; then
    "$_MUX_BIN" send-keys -t "$name" -l -- "$text" && "$_MUX_BIN" send-keys -t "$name" Enter
  else
    "$_MUX_BIN" --session "$name" action write-chars -- "$text" 2>/dev/null \
      && "$_MUX_BIN" --session "$name" action write 13 2>/dev/null
  fi
}

# mux_capture NAME -> sichtbarer Pane-Inhalt nach STDOUT
#   Achtung: bei zellij nur gegen Sessions mit Client zuverlässig (s. o.).
mux_capture() {
  _mux_resolve || return 1
  local name="$1"
  if [ "$_MUX_BACKEND" = tmux ]; then
    "$_MUX_BIN" capture-pane -t "$name" -p 2>/dev/null
  else
    "$_MUX_BIN" --session "$name" action dump-screen 2>/dev/null
  fi
}

# mux_kill NAME -> Session beenden
mux_kill() {
  _mux_resolve || return 1
  local name="$1"
  if [ "$_MUX_BACKEND" = tmux ]; then
    "$_MUX_BIN" kill-session -t "$name" 2>/dev/null
  else
    # zellij: delete-session/kill-session liefern gegen sehr junge Sessions einen
    # unzuverlässigen Exit-Code (Race: rc!=0 "not found", obwohl der Kill GREIFT).
    # Darum am RESULTAT messen (Session weg?), nicht am rc des Kill-Verbs.
    "$_MUX_BIN" delete-session "$name" --force >/dev/null 2>&1 \
      || "$_MUX_BIN" kill-session "$name" >/dev/null 2>&1 || true
    ! mux_has "$name"   # rc 0 ⇔ Session ist tatsächlich weg
  fi
}

# ---------------------------------------------------------------------------
# Self-Test (kein Gate, nur Sanity):  bash scripts/lib/mux.sh --self-test
# Feuert NUR bei direkter Ausführung, nicht beim Sourcen (sonst würde der Test
# bei `colonel.sh --self-test` o. ä. fälschlich mit-triggern).
# ---------------------------------------------------------------------------
if [ "${BASH_SOURCE[0]}" = "${0}" ] && [ "${1:-}" = "--self-test" ]; then
  set -uo pipefail
  _mux_resolve || exit 1
  echo "mux self-test — Backend: $_MUX_BACKEND ($_MUX_BIN)"
  t="muxselftest_$$"
  mux_has "$t" && { echo "FAIL: $t existiert schon"; exit 1; }
  mux_spawn "$t" "for i in 1 2 3; do echo tick-\$i >> /tmp/$t.log; sleep 1; done" || { echo "FAIL: spawn"; exit 1; }
  sleep 1
  mux_has "$t"        && echo "ok: has nach spawn"        || { echo "FAIL: has"; exit 1; }
  mux_list | grep -qx "$t" && echo "ok: list enthält Session" || { echo "FAIL: list"; exit 1; }
  sleep 3
  if [ -f "/tmp/$t.log" ] && grep -q tick-3 "/tmp/$t.log"; then echo "ok: Command lief in Session"; else echo "FAIL: Command lief nicht"; mux_kill "$t"; exit 1; fi
  mux_kill "$t"; sleep 1
  mux_has "$t" && { echo "FAIL: nach kill noch da"; exit 1; } || echo "ok: kill"
  rm -f "/tmp/$t.log"
  echo "SELF-TEST GRÜN ✅ ($(mux_backend))"
fi
