#!/usr/bin/env bash
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

python3 - <<'PY'
import json, pathlib, sys
p = pathlib.Path('.ralph/agent/review-cycle/review-cycle.latest.json')
if not p.exists():
    print('Missing review-cycle.latest.json')
    sys.exit(1)
obj = json.loads(p.read_text())
ok = bool(obj.get('milestone_complete')) and len(obj.get('review_items', [])) >= 0
print('milestone_complete=true' if ok else 'milestone_complete=false')
sys.exit(0 if ok else 1)
PY
