#!/usr/bin/env bash
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

source scripts/review_cycle/lib/speech.sh
source scripts/review_cycle/lib/idempotency.sh

python3 - <<'PY'
import json, pathlib, subprocess
inp = pathlib.Path('.ralph/agent/review-cycle/task-events.normalized.jsonl')
outp = pathlib.Path('.ralph/agent/review-cycle/speech-events.jsonl')
latest = None
emitted = 0
if inp.exists():
    for ln in inp.read_text().splitlines():
        if not ln.strip():
            continue
        ev = json.loads(ln)
        event_id = ev.get('event_id', 'task-unknown')
        task_number = ev.get('task_number', '').strip()
        if not task_number:
            continue
        key = f"task:{event_id}:{task_number}"
        seen = subprocess.run(['bash','-lc', f"source scripts/review_cycle/lib/idempotency.sh; idempotency_seen '{key}' && echo yes || echo no"], capture_output=True, text=True, check=True).stdout.strip()
        if seen == 'yes':
            continue
        desc = ev.get('hilarious_description','').strip()
        phrase = subprocess.run(['bash','-lc', f"scripts/review_cycle/build_task_done_phrase.sh '{task_number}' '{desc}'"], capture_output=True, text=True, check=True).stdout.strip()
        subprocess.run(['bash','-lc', f"source scripts/review_cycle/lib/idempotency.sh; idempotency_record '{key}'"], check=True)
        subprocess.run(['bash','-lc', f"source scripts/review_cycle/lib/speech.sh; speak_text \"{phrase}\""], check=True)
        payload = {
            "event_type": "task-completion",
            "event_id": event_id,
            "idempotency_key": key,
            "payload": {
                "task_number": task_number,
                "hilarious_description": desc if desc else subprocess.run(['bash','-lc', f"scripts/review_cycle/default_hilarious_description.sh '{task_number}'"], capture_output=True, text=True, check=True).stdout.strip(),
                "phrase": phrase
            }
        }
        with outp.open('a') as f:
            f.write(json.dumps(payload) + "\n")
        latest = payload
        emitted += 1

latest_p = pathlib.Path('.ralph/agent/review-cycle/speech-events.latest.json')
if latest:
    latest_p.write_text(json.dumps(latest, indent=2))
print(f"task completion emitted={emitted}")
PY
