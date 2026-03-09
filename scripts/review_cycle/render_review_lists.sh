#!/usr/bin/env bash
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

python3 - <<'PY'
import json, pathlib
classified = json.loads(pathlib.Path('.ralph/agent/review-cycle/review-items.classified.json').read_text())
merge_now = classified.get('merge_now', [])
wait = classified.get('wait', [])
lines = ["# Review Lists", "", "## merge-now", ""]
for item in merge_now:
    lines.append(f"- {item['id']} ({item['risk_level']}): {item['rationale']}")
lines += ["", "## wait", ""]
for item in wait:
    lines.append(f"- {item['id']} ({item['risk_level']}): {item['rationale']} | trigger: {item.get('next_review_trigger','n/a')}")
path = pathlib.Path('.ralph/agent/review-cycle/review-lists.md')
path.write_text("\n".join(lines) + "\n")
print(f"Wrote {path}")
PY
