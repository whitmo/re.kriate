#!/usr/bin/env bash
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

python3 - <<'PY'
import json, pathlib, sys
classified = json.loads(pathlib.Path('.ralph/agent/review-cycle/review-items.classified.json').read_text())
merge_ids = {i['id'] for i in classified.get('merge_now', [])}
wait_ids = {i['id'] for i in classified.get('wait', [])}
if merge_ids & wait_ids:
    print('ERROR: overlap between merge-now and wait lists')
    sys.exit(1)
if not (merge_ids or wait_ids):
    print('ERROR: no classified items found')
    sys.exit(1)
print(f"US1 validation passed: merge-now={len(merge_ids)}, wait={len(wait_ids)}")
PY
