#!/usr/bin/env bash
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

python3 - <<'PY'
import json, pathlib, datetime
classified = json.loads(pathlib.Path('.ralph/agent/review-cycle/review-items.classified.json').read_text())
review_items = classified.get('merge_now', []) + classified.get('wait', [])
out = {
  "cycle_id": datetime.datetime.utcnow().strftime("cycle-%Y%m%d-%H%M%S"),
  "started_at": datetime.datetime.utcnow().isoformat() + "Z",
  "completed_at": datetime.datetime.utcnow().isoformat() + "Z",
  "milestone_complete": True,
  "artifact_paths": ["docs/code-review.html", "docs/branch-gap-analysis.html"],
  "review_items": review_items
}
path = pathlib.Path('.ralph/agent/review-cycle/review-cycle.latest.json')
path.write_text(json.dumps(out, indent=2))
print(f"Wrote {path} ({len(review_items)} review_items)")
PY
