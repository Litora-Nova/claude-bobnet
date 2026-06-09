#!/usr/bin/env bash
# tests/dashboard_po_tasks_file_spec.sh — Black-Box-Spec gegen die dokumentierte
# Vorrang-Kette in dashboard/server/utils/po-tasks-file.mjs (White-Label-Rename
# `austin.tasks.md` → `po.tasks.md`, ohne Bestandsinstanzen zu brechen):
#   1. po.tasks.md existiert      → die (neue/migrierte Instanz)
#   2. sonst austin.tasks.md da   → die (Legacy: read+write, nicht verwaisen lassen)
#   3. sonst                      → Default po.tasks.md (neu anlegen)
# Diese Spec ist der Schutz, dass der Rename die Live-Instanzen (echte
# austin.tasks.md) nicht still leerlaufen lässt.
# Aufruf der PURE function tasksFile() + Konstanten direkt via node.
set -uo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/_helper.sh"

MJS="$ENGINE_ROOT/dashboard/server/utils/po-tasks-file.mjs"

# t '<dir>' : druckt den von tasksFile(dir) gelieferten Pfad (file://-Import wie activity/beats).
t() { node --input-type=module -e "import {tasksFile} from 'file://$MJS'; console.log(tasksFile(process.argv[1]))" "$1"; }
# k '<name>' : druckt eine exportierte Konstante (Kanon-Check).
k() { node --input-type=module -e "import * as M from 'file://$MJS'; console.log(M[process.argv[1]])" "$1"; }

echo "po-tasks-file.mjs — Vorrang-Ketten-Spec"

# ── Konstanten-Kanon (Vertrag, an dem die Instanzen hängen) ───────────────────
it "PO_TASKS = 'po.tasks.md'"
eq "$(k PO_TASKS)" "po.tasks.md"

it "LEGACY_PO_TASKS = 'austin.tasks.md' (Legacy-Bestandsname bleibt erkannt)"
eq "$(k LEGACY_PO_TASKS)" "austin.tasks.md"

# ── (a) Backward-Compat: nur Legacy-Datei → Legacy-Pfad ───────────────────────
it "(a) nur austin.tasks.md im Dir → tasksFile() liefert den austin.tasks.md-Pfad (Bestandsinstanz bricht NICHT)"
DA="$(mktemp -d "${TMPDIR:-/tmp}/po-tasks-a.XXXXXX")"
: > "$DA/austin.tasks.md"
eq "$(t "$DA")" "$DA/austin.tasks.md"
rm -rf "$DA"

# ── (b) Neuer Vorrang: po.tasks.md gewinnt, auch neben Legacy ─────────────────
it "(b1) nur po.tasks.md → tasksFile() liefert po.tasks.md (neuer Default)"
DB1="$(mktemp -d "${TMPDIR:-/tmp}/po-tasks-b1.XXXXXX")"
: > "$DB1/po.tasks.md"
eq "$(t "$DB1")" "$DB1/po.tasks.md"
rm -rf "$DB1"

it "(b2) po.tasks.md UND austin.tasks.md → po.tasks.md hat Vorrang (kein doppeltes File)"
DB2="$(mktemp -d "${TMPDIR:-/tmp}/po-tasks-b2.XXXXXX")"
: > "$DB2/po.tasks.md"
: > "$DB2/austin.tasks.md"
eq "$(t "$DB2")" "$DB2/po.tasks.md"
rm -rf "$DB2"

# ── (c) Default für neue Instanzen: keine der beiden → po.tasks.md ────────────
it "(c) weder po.tasks.md noch austin.tasks.md → tasksFile() liefert po.tasks.md (Default neu)"
DC="$(mktemp -d "${TMPDIR:-/tmp}/po-tasks-c.XXXXXX")"
eq "$(t "$DC")" "$DC/po.tasks.md"
rm -rf "$DC"

summary
