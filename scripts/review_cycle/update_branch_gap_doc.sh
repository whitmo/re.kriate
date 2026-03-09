#!/usr/bin/env bash
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

DOC="docs/branch-gap-analysis.html"
MAP_FILE=".ralph/agent/review-cycle/gap-mapping.md"
[ -f "$DOC" ] || { echo "Missing $DOC"; exit 1; }
[ -f "$MAP_FILE" ] || { echo "Missing $MAP_FILE"; exit 1; }

START='<!-- REVIEW-CYCLE-GAPS-START -->'
END='<!-- REVIEW-CYCLE-GAPS-END -->'
CONTENT="$(sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g' "$MAP_FILE")"
BLOCK="$START\n<pre>\n$CONTENT\n</pre>\n$END"

if rg -q "$START" "$DOC"; then
  perl -0777 -i -pe "s|$START.*?$END|$BLOCK|s" "$DOC"
else
  printf '\n%s\n' "$BLOCK" >> "$DOC"
fi

echo "Updated $DOC with gap mapping section"
