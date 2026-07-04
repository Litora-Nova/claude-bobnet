#!/usr/bin/env bash
# tests/context_trim_spec.sh — Black-Box-Spec für den context-trim PostToolUse-Hook
# (hooks/context-trim.py). Prüft: struktur-erhaltendes Kürzen des größten Text-Feldes,
# Stash + Pointer, und vor allem die FAIL-SAFE-Eigenschaft (jede Unsicherheit → pass-through).
# Hermetisch: Payloads via STDIN, Stash in mktemp, kein git/mux. Braucht python3.
set -uo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/_helper.sh"

PY="$ENGINE_ROOT/hooks/context-trim.py"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
ST="$TMP/stash"

have_py=1; command -v python3 >/dev/null 2>&1 || have_py=0

run_ct() { # $1=payload-JSON · $2=threshold(default 100) → setzt CT_OUT + CT_RC
  CT_OUT="$(printf '%s' "$1" | CT_STASH_DIR="$ST" CT_THRESHOLD_BYTES="${2:-100}" \
    CT_HEAD_LINES=3 CT_TAIL_LINES=2 python3 "$PY" 2>/dev/null)"; CT_RC=$?
}
is_json() { printf '%s' "$1" | python3 -c 'import sys,json; json.load(sys.stdin)' >/dev/null 2>&1; }
# Payload-Generatoren (jq-frei, JSON-sicher via python)
mk_bash() { python3 -c "import json; print(json.dumps({'tool_name':'Bash','tool_response':{'stdout':chr(10).join('l%d'%i for i in range($1)),'stderr':'warnmsg','exit_code':0}}))"; }
mk_read() { python3 -c "import json; print(json.dumps({'tool_name':'Read','tool_response':{'content':'x'*$1}}))"; }
mk_str()  { python3 -c "import json; print(json.dumps({'tool_name':'X','tool_response':'y'*$1}))"; }

echo "context_trim_spec:"
it "hooks/context-trim.py + .sh existieren"; ok bash -c 'test -f "'"$PY"'" && test -x "'"$ENGINE_ROOT"'/hooks/context-trim.sh"'

if [ "$have_py" = 0 ]; then
  it "python3 vorhanden"; printf '  ⊘ SKIP: kein python3 — context-trim nicht prüfbar (CI-sicher grün)\n'
  summary; return 0 2>/dev/null || exit 0
fi

# --- Bash: übergroßes stdout → struktur-erhaltend gekürzt ---
run_ct "$(mk_bash 200)"
it "Bash riesig → Output nicht leer (gekürzt)";        neq "$CT_OUT" ""
it "Output ist wohlgeformtes JSON";                    ok is_json "$CT_OUT"
it "Output trägt hookEventName PostToolUse";           contains "$CT_OUT" '"hookEventName": "PostToolUse"'
it "stdout wird gekürzt + Pointer";                    contains "$CT_OUT" "context-trim:"
it "Pointer nennt den Stash-Pfad";                     contains "$CT_OUT" "stashed at"
it "stderr-Feld bleibt erhalten (struktur-erhaltend)"; contains "$CT_OUT" "warnmsg"
it "exit_code-Feld bleibt erhalten";                   contains "$CT_OUT" '"exit_code": 0'

# --- Pass-through: unter der Schwelle ---
run_ct '{"tool_name":"Bash","tool_response":{"stdout":"kurz","exit_code":0}}'
it "kleines stdout → pass-through (leer)"; eq "$CT_OUT" ""
it "pass-through → Exit 0";                eq "$CT_RC" "0"

# --- Read: content gekürzt ---
run_ct "$(mk_read 5000)"
it "Read riesiges content → gekürzt + Pointer"; contains "$CT_OUT" "stashed at"
it "Read-Output wohlgeformtes JSON";            ok is_json "$CT_OUT"

# --- tool_response als STRING ---
run_ct "$(mk_str 5000)"
it "String-tool_response riesig → Output nicht leer"; neq "$CT_OUT" ""
ct_type() { printf '%s' "$1" | python3 -c 'import sys,json; print(type(json.load(sys.stdin)["hookSpecificOutput"]["updatedToolOutput"]).__name__)' 2>/dev/null; }
it "String-Fall → updatedToolOutput ist String"; eq "$(ct_type "$CT_OUT")" "str"
run_ct "$(mk_bash 200)"
it "Bash-Fall → updatedToolOutput ist Objekt (struktur-erhaltend)"; eq "$(ct_type "$CT_OUT")" "dict"

# --- FAIL-SAFE-Fälle: immer pass-through (leer, Exit 0) ---
run_ct 'DAS IST KEIN JSON'
it "kaputtes JSON → pass-through (leer)"; eq "$CT_OUT" ""
it "kaputtes JSON → Exit 0";              eq "$CT_RC" "0"
run_ct '{"tool_name":"Bash"}'
it "fehlendes tool_response → pass-through"; eq "$CT_OUT" ""
run_ct '{"tool_name":"X","tool_response":12345}'
it "tool_response als Zahl → pass-through (nicht kürzbar)"; eq "$CT_OUT" ""
run_ct '{"tool_name":"X","tool_response":{"ok":true,"n":5}}'
it "dict ohne String-Felder → pass-through"; eq "$CT_OUT" ""

# --- Stash-File real geschrieben ---
run_ct "$(mk_bash 200)"
it "Stash-File für den Volltext angelegt"; ok bash -c 'ls "'"$ST"'"/trim-*.txt >/dev/null 2>&1'

# --- wenige, aber riesige Zeilen → Zeichen-Kürzung greift trotzdem ---
run_ct '{"tool_name":"X","tool_response":{"stdout":"'"$(python3 -c 'print("z"*6000,end="")')"'"}}'
it "eine riesige Zeile → trotzdem gekürzt + Pointer"; contains "$CT_OUT" "context-trim:"

summary
