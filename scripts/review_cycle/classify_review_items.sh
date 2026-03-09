#!/usr/bin/env bash
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

python3 - <<'PY'
import json, pathlib, re

raw = json.loads(pathlib.Path('.ralph/agent/review-cycle/review-items.raw.json').read_text())
merge_now, wait = [], []
for item in raw.get('items', []):
    ref = item.get('ref','')
    src = item.get('source','remote-branch')
    origin_group = 'multiclaude' if 'multiclaude' in ref else ('core' if ref.startswith('origin/') else 'other')
    risky = bool(re.search(r'(wip|draft|blocked|hold|spike)', ref, re.I))
    status = 'wait' if risky else 'merge-now'
    risk_level = 'high' if re.search(r'(hotfix|security|auth|payment)', ref, re.I) else ('low' if re.search(r'(docs|cleanup|refactor)', ref, re.I) else 'medium')
    rec = {
        "id": item["id"],
        "source": src,
        "origin_group": origin_group,
        "status": status,
        "risk_level": risk_level,
        "rationale": "contains blocked/wip marker" if risky else "no blocking markers detected"
    }
    if status == 'wait':
      rec["next_review_trigger"] = "after dependency or reviewer unblock"
      wait.append(rec)
    else:
      merge_now.append(rec)

out = {"generated_on": raw.get('generated_on'), "merge_now": merge_now, "wait": wait}
path = pathlib.Path('.ralph/agent/review-cycle/review-items.classified.json')
path.write_text(json.dumps(out, indent=2))
print(f"Wrote {path} (merge_now={len(merge_now)}, wait={len(wait)})")
PY
