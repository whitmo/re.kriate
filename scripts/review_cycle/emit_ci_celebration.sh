#!/usr/bin/env bash
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

source scripts/review_cycle/lib/speech.sh
source scripts/review_cycle/lib/idempotency.sh

STATE_FILE=".ralph/agent/review-cycle/voice-rotation-state.json"
EVENTS_IN=".ralph/agent/review-cycle/ci-events.normalized.jsonl"
EVENTS_OUT=".ralph/agent/review-cycle/speech-events.jsonl"
LATEST_JSON=".ralph/agent/review-cycle/speech-events.latest.json"
PHRASE="HOOOOOORAY!!!"

python3 - <<'PY'
import json, pathlib
st = pathlib.Path('.ralph/agent/review-cycle/voice-rotation-state.json')
if not st.exists():
    st.write_text(json.dumps({"voices":["Alex","Samantha","Victoria","Fred"],"current_index":0,"last_event_id":None}, indent=2))
PY

python3 - <<'PY'
import json, pathlib, subprocess
state_p = pathlib.Path('.ralph/agent/review-cycle/voice-rotation-state.json')
state = json.loads(state_p.read_text())
voices = state.get('voices', ['Alex'])
idx = int(state.get('current_index', 0))

events = []
in_p = pathlib.Path('.ralph/agent/review-cycle/ci-events.normalized.jsonl')
if in_p.exists():
    events = [json.loads(l) for l in in_p.read_text().splitlines() if l.strip()]

out_lines = []
latest = None
for ev in events:
    branch = ev.get('branch_name','')
    status = ev.get('ci_status','')
    if status != 'passed' or not branch.startswith('origin/'):
        continue
    is_new = subprocess.run(['bash','-lc', f"scripts/review_cycle/is_new_branch.sh '{branch}'"], capture_output=True, text=True, check=True).stdout.strip()
    if is_new != 'true':
        continue
    event_id = ev.get('event_id','ci-unknown')
    key = f"ci:{event_id}:{branch}"
    seen = subprocess.run(['bash','-lc', f"source scripts/review_cycle/lib/idempotency.sh; idempotency_seen '{key}' && echo yes || echo no"], capture_output=True, text=True, check=True).stdout.strip()
    if seen == 'yes':
        continue
    voice = voices[idx % len(voices)]
    idx += 1
    payload = {
        "event_type": "ci-celebration",
        "event_id": event_id,
        "idempotency_key": key,
        "payload": {
            "branch_name": branch,
            "ci_status": "passed",
            "is_new_branch": True,
            "phrase": "HOOOOOORAY!!!",
            "voice": voice
        }
    }
    subprocess.run(['bash','-lc', f"source scripts/review_cycle/lib/idempotency.sh; idempotency_record '{key}'"], check=True)
    subprocess.run(['bash','-lc', f"source scripts/review_cycle/lib/speech.sh; speak_text '{payload['payload']['phrase']}' '{voice}'"], check=True)
    out_lines.append(json.dumps(payload))
    latest = payload

out_p = pathlib.Path('.ralph/agent/review-cycle/speech-events.jsonl')
if out_lines:
    with out_p.open('a') as f:
        for l in out_lines:
            f.write(l + "\n")
state['current_index'] = idx % len(voices)
state['last_event_id'] = latest['event_id'] if latest else state.get('last_event_id')
state_p.write_text(json.dumps(state, indent=2))

latest_p = pathlib.Path('.ralph/agent/review-cycle/speech-events.latest.json')
if latest:
    latest_p.write_text(json.dumps(latest, indent=2))
elif not latest_p.exists():
    latest_p.write_text(json.dumps({
        "event_type": "ci-celebration",
        "event_id": "none",
        "idempotency_key": "none",
        "payload": {
            "branch_name": "origin/none",
            "ci_status": "passed",
            "is_new_branch": True,
            "phrase": "HOOOOOORAY!!!",
            "voice": voices[0]
        }
    }, indent=2))
print(f"processed={len(events)} emitted={len(out_lines)}")
PY
