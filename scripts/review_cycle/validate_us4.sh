#!/usr/bin/env bash
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

python3 - <<'PY'
import json, pathlib, sys
p = pathlib.Path('.ralph/agent/review-cycle/speech-events.jsonl')
if not p.exists():
    print('ERROR: missing speech-events.jsonl')
    sys.exit(1)
keys = set()
for line in p.read_text().splitlines():
    if not line.strip():
        continue
    obj = json.loads(line)
    key = obj.get('idempotency_key')
    if key in keys:
        print('ERROR: duplicate idempotency key found')
        sys.exit(1)
    keys.add(key)
print(f'US4 validation passed: {len(keys)} unique speech events')
PY
