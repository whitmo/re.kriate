#!/usr/bin/env bash
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

python3 - <<'PY'
import json, pathlib
summary = json.loads(pathlib.Path('.ralph/agent/review-cycle/task-scope-summary.latest.json').read_text())
lines = ["## Gap Mapping", ""]
if not summary.get('wait'):
    lines.append('- No current gaps: wait list is empty.')
else:
    for idx, w in enumerate(summary['wait'], 1):
        task = summary['next_tasks'][idx-1] if idx-1 < len(summary['next_tasks']) else None
        lines.append(f"- GAP-{idx:03d}: {w['item']}")
        lines.append(f"  - Reason: {w['blocking_reason']}")
        lines.append(f"  - Next trigger: {w['next_review_trigger']}")
        if task:
            lines.append(f"  - Task candidate: {task['task_id']} ({task['title']})")
path = pathlib.Path('.ralph/agent/review-cycle/gap-mapping.md')
path.write_text("\n".join(lines) + "\n")
print(f"Wrote {path}")
PY
