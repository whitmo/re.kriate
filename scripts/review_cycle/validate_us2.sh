#!/usr/bin/env bash
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

python3 - <<'PY'
import json, pathlib, sys
summary = json.loads(pathlib.Path('.ralph/agent/review-cycle/task-scope-summary.latest.json').read_text())
wait = summary.get('wait', [])
next_tasks = summary.get('next_tasks', [])
if len(wait) != len(next_tasks):
    print(f"ERROR: wait items ({len(wait)}) and next_tasks ({len(next_tasks)}) mismatch")
    sys.exit(1)
print(f"US2 validation passed: wait={len(wait)}, next_tasks={len(next_tasks)}")
PY
