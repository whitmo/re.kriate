#!/usr/bin/env bash
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

python3 - <<'PY'
import json, pathlib
classified = json.loads(pathlib.Path('.ralph/agent/review-cycle/review-items.classified.json').read_text())
wait_items = classified.get('wait', [])
tasks = []
for idx, item in enumerate(wait_items, 1):
    tid = f"TC{idx:03d}"
    tasks.append({
        "task_id": tid,
        "title": f"Resolve blocker for {item['id']}",
        "priority": "P1" if item.get('risk_level') == 'high' else "P2",
        "why_now": item.get('rationale', 'required to unblock merge'),
        "simplicity_choice": "minimal unblock change",
        "alternatives_rejected": ["full refactor now (too broad for unblock)"]
    })
out = {
    "feature": "branch-review-followups",
    "merge_now": [i['id'] for i in classified.get('merge_now', [])],
    "wait": [
        {
            "item": i['id'],
            "blocking_reason": i.get('rationale', 'unknown blocker'),
            "next_review_trigger": i.get('next_review_trigger', 'after unblock')
        }
        for i in wait_items
    ],
    "next_tasks": tasks
}
path = pathlib.Path('.ralph/agent/review-cycle/task-scope-summary.latest.json')
path.write_text(json.dumps(out, indent=2))
print(f"Wrote {path} (next_tasks={len(tasks)})")
PY
