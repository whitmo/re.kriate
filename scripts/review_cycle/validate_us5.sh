#!/usr/bin/env bash
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

python3 - <<'PY'
import json, pathlib, sys
p = pathlib.Path('.ralph/agent/review-cycle/speech-events.jsonl')
if not p.exists():
    print('ERROR: missing speech-events.jsonl')
    sys.exit(1)
ok = 0
for line in p.read_text().splitlines():
    if not line.strip():
        continue
    o = json.loads(line)
    if o.get('event_type') == 'task-completion':
        phrase = o.get('payload', {}).get('phrase', '')
        if not phrase.startswith('DONE '):
            print('ERROR: invalid task completion phrase')
            sys.exit(1)
        ok += 1
print(f'US5 validation passed: {ok} task-completion events')
PY
