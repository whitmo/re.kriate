#!/usr/bin/env bash
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

python3 - <<'PY'
import json, pathlib, sys
root = pathlib.Path('.')
checks = [
    (root/'.ralph/agent/review-cycle/review-cycle.latest.json', root/'specs/001-branch-review-followups/contracts/review-cycle.schema.json'),
    (root/'.ralph/agent/review-cycle/speech-events.latest.json', root/'specs/001-branch-review-followups/contracts/speech-event.schema.json'),
    (root/'.ralph/agent/review-cycle/task-scope-summary.latest.json', root/'specs/001-branch-review-followups/contracts/task-scope-summary.schema.json'),
]
for data_path, schema_path in checks:
    if not data_path.exists():
        print(f"WARN: missing {data_path}")
        continue
    data = json.loads(data_path.read_text())
    schema = json.loads(schema_path.read_text())
    required = schema.get('required', [])
    missing = [k for k in required if k not in data]
    if missing:
        print(f"ERROR: {data_path} missing required keys: {missing}")
        sys.exit(1)
print('Contract validation passed (top-level required keys).')
PY
