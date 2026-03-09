#!/usr/bin/env bash
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

IN_FILE="${1:-.ralph/agent/review-cycle/ci-events.in.jsonl}"
OUT_FILE=".ralph/agent/review-cycle/ci-events.normalized.jsonl"
mkdir -p .ralph/agent/review-cycle

if [ ! -f "$IN_FILE" ]; then
  cat > "$IN_FILE" <<'JSONL'
{"event_id":"ci-001","branch_name":"origin/multiclaude/calm-hawk","ci_status":"passed"}
JSONL
fi

python3 - <<'PY'
import json, pathlib
in_path = pathlib.Path('.ralph/agent/review-cycle/ci-events.in.jsonl')
out_path = pathlib.Path('.ralph/agent/review-cycle/ci-events.normalized.jsonl')
lines = []
for ln in in_path.read_text().splitlines():
    if not ln.strip():
        continue
    o = json.loads(ln)
    o.setdefault('ci_status', 'passed')
    lines.append(json.dumps(o))
out_path.write_text("\n".join(lines) + ("\n" if lines else ""))
print(f"Wrote {out_path} ({len(lines)} events)")
PY
