#!/usr/bin/env bash
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

IN_FILE="${1:-.ralph/agent/review-cycle/task-events.in.jsonl}"
OUT_FILE=".ralph/agent/review-cycle/task-events.normalized.jsonl"
mkdir -p .ralph/agent/review-cycle

if [ ! -f "$IN_FILE" ]; then
  cat > "$IN_FILE" <<'JSONL'
{"event_id":"task-001","task_number":"T001","hilarious_description":"the yak has been tastefully shaved"}
JSONL
fi

python3 - <<'PY'
import json, pathlib
in_path = pathlib.Path('.ralph/agent/review-cycle/task-events.in.jsonl')
out_path = pathlib.Path('.ralph/agent/review-cycle/task-events.normalized.jsonl')
rows = []
for ln in in_path.read_text().splitlines():
    if not ln.strip():
        continue
    o = json.loads(ln)
    if 'task_number' in o and o['task_number']:
        rows.append(o)
out_path.write_text('\n'.join(json.dumps(r) for r in rows) + ('\n' if rows else ''))
print(f"Wrote {out_path} ({len(rows)} events)")
PY
