#!/usr/bin/env python3
# hooks/context-trim.py — PostToolUse-Logik (Token-Win, Headroom-Konzept nativ, Issue context-trim).
#
# Kürzt das GRÖSSTE Text-Feld eines übergroßen Tool-Outputs (Kopf+Schwanz+Pointer), stasht den
# Volltext und lässt ALLE anderen Felder unangetastet → updatedToolOutput spiegelt die Struktur von
# tool_response. Damit immun gegen die (noch nicht stabilisierte) Schema-Unsicherheit Objekt-vs-String.
#
# FAIL-SAFE: jede Parse-Unsicherheit / jeder Fehler / unter der Schwelle → pass-through (exit 0, NICHTS
# auf stdout → Claude Code nutzt den Original-Output unverändert). Reversibel: der Volltext wird
# gestasht und der Pointer nennt den Pfad (Bob holt Details on-demand via Read/grep). Schlägt das
# Stashen fehl, wird NICHT gekürzt (Reversibilität ist das Sicherheitsnetz).
import sys, os, json, hashlib


def main():
    data = json.loads(sys.stdin.read())          # Parse-Fehler → except → pass-through
    tr = data.get("tool_response", None)
    if tr is None:
        return

    threshold = int(os.environ.get("CT_THRESHOLD_BYTES", "8000"))
    head_n    = int(os.environ.get("CT_HEAD_LINES", "120"))
    tail_n    = int(os.environ.get("CT_TAIL_LINES", "40"))
    stash_dir = os.environ.get("CT_STASH_DIR") or os.path.join(
        os.environ.get("TMPDIR", "/tmp"), "bobnet-context-trim")

    # Ziel-Text + Container bestimmen (größtes String-Feld bei dict; ganzer String bei str)
    if isinstance(tr, str):
        target_key, text = None, tr
    elif isinstance(tr, dict):
        str_fields = {k: v for k, v in tr.items() if isinstance(v, str)}
        if not str_fields:
            return
        target_key = max(str_fields, key=lambda k: len(str_fields[k]))
        text = str_fields[target_key]
    else:
        return

    if len(text.encode("utf-8", "replace")) <= threshold:
        return  # unter der Schwelle → pass-through

    tool = str(data.get("tool_name", "tool"))
    orig_lines = text.count("\n") + 1
    orig_bytes = len(text.encode("utf-8", "replace"))

    # Volltext stashen — scheitert das, NICHT kürzen (sonst irreversibler Verlust)
    try:
        os.makedirs(stash_dir, exist_ok=True)
        h = hashlib.sha1(text.encode("utf-8", "replace")).hexdigest()[:12]
        safe_tool = "".join(c if c.isalnum() else "_" for c in tool)[:32]
        stash_path = os.path.join(stash_dir, "trim-%s-%s.txt" % (safe_tool, h))
        with open(stash_path, "w", encoding="utf-8") as f:
            f.write(text)
    except Exception:
        return

    pointer = ("\n…[context-trim: original %d lines / %d bytes — kept head %d + tail %d. "
               "Full output stashed at %s — retrieve with Read('%s', offset=N) or grep.]…\n"
               % (orig_lines, orig_bytes, head_n, tail_n, stash_path, stash_path))

    lines = text.split("\n")
    if len(lines) > head_n + tail_n + 1:
        trimmed = "\n".join(lines[:head_n]) + pointer + "\n".join(lines[-tail_n:])
    else:                                        # wenige, aber riesige Zeilen → nach Zeichen kürzen
        trimmed = text[: threshold // 2] + pointer + text[-(threshold // 4):]

    updated = trimmed if target_key is None else {**tr, target_key: trimmed}
    print(json.dumps({"hookSpecificOutput": {
        "hookEventName": "PostToolUse",
        "updatedToolOutput": updated,
    }}))


try:
    main()
except Exception:
    pass                                         # FAIL-SAFE: niemals den Tool-Output korrumpieren
sys.exit(0)
