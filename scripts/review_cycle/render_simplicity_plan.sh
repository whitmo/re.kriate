#!/usr/bin/env bash
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

python3 - <<'PY'
import json, pathlib
summary = json.loads(pathlib.Path('.ralph/agent/review-cycle/task-scope-summary.latest.json').read_text())
lines = ["## Simplicity-First Follow-up Plan", ""]
if not summary.get('next_tasks'):
    lines.append("- No wait items currently require follow-up tasks.")
else:
    for t in summary['next_tasks']:
        lines.append(f"- {t['task_id']}: {t['title']} ({t['priority']})")
        lines.append(f"  - Simple path: {t.get('simplicity_choice','n/a')}")
        for alt in t.get('alternatives_rejected', []):
            lines.append(f"  - Rejected: {alt}")
path = pathlib.Path('.ralph/agent/review-cycle/simplicity-plan.md')
path.write_text("\n".join(lines) + "\n")
print(f"Wrote {path}")
PY
