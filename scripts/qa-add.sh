#!/usr/bin/env bash
# qa-add.sh — legt einen Q&A-Eintrag in <STANDUP_DIR>/qa/<datum>-<slug>.md an.
# Aufruf:  qa-add.sh "<frage>" "<antwort>"
# Antwort darf Markdown enthalten (Listen, **fett**, `code`, mehrere Zeilen via \n).
#
# Env:
#   STANDUP_DIR     Basis (Default: Verzeichnis dieses Scripts) — qa/ darunter
#   QA_ASKED_BY     Frontmatter asked_by (Default: Austin)
#   QA_ANSWERED_BY  Frontmatter answered_by + Body-Label (Default: Bob)
set -euo pipefail

if [ "$#" -lt 2 ]; then
  echo "Aufruf: $0 \"<frage>\" \"<antwort>\"" >&2
  echo "Antwort darf Markdown sein (mehrere Zeilen via literalem \\n im String)." >&2
  exit 2
fi

Q="$1"; A="$2"
DIR="${STANDUP_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
QA_DIR="$DIR/qa"
ASKED_BY="${QA_ASKED_BY:-Austin}"
ANSWERED_BY="${QA_ANSWERED_BY:-Bob}"
mkdir -p "$QA_DIR"

DATE_SHORT="$(date +%Y-%m-%d)"
STAMP="$(date +%Y-%m-%dT%H:%M)"

# Slug: lowercased, Umlaute ersetzt, nicht-alnum → '-', auf 50 Zeichen.
slug() {
  echo "$1" | tr '[:upper:]' '[:lower:]' \
    | sed 's/ä/ae/g; s/ö/oe/g; s/ü/ue/g; s/ß/ss/g' \
    | sed 's/[^a-z0-9]\{1,\}/-/g; s/^-//; s/-$//' \
    | cut -c1-50
}
SLUG="$(slug "$Q")"; [ -z "$SLUG" ] && SLUG="frage"

FILE="$QA_DIR/$DATE_SHORT-$SLUG.md"
n=2
while [ -e "$FILE" ]; do FILE="$QA_DIR/$DATE_SHORT-$SLUG-$n.md"; n=$((n+1)); done

ANSWER_RENDERED="$(printf '%b' "$A")"

cat > "$FILE" <<EOF
---
asked_by: $ASKED_BY
answered_by: $ANSWERED_BY
created: $STAMP
answered: $STAMP
dismissed: false
dismissed_at: ""
---

# Q · $Q

**Antwort ($ANSWERED_BY):**

$ANSWER_RENDERED
EOF

echo "$FILE"
