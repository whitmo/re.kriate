#!/usr/bin/env bash
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

DOC="docs/code-review.html"
PLAN_FILE=".ralph/agent/review-cycle/simplicity-plan.md"
[ -f "$DOC" ] || { echo "Missing $DOC"; exit 1; }
[ -f "$PLAN_FILE" ] || { echo "Missing $PLAN_FILE"; exit 1; }

START='<!-- REVIEW-CYCLE-SIMPLICITY-START -->'
END='<!-- REVIEW-CYCLE-SIMPLICITY-END -->'
CONTENT="$(sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g' "$PLAN_FILE")"
BLOCK="$START\n<pre>\n$CONTENT\n</pre>\n$END"

if rg -q "$START" "$DOC"; then
  perl -0777 -i -pe "s|$START.*?$END|$BLOCK|s" "$DOC"
else
  printf '\n%s\n' "$BLOCK" >> "$DOC"
fi

echo "Updated $DOC with simplicity section"
