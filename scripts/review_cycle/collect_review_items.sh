#!/usr/bin/env bash
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

python3 - <<'PY'
import json, subprocess

def run(cmd):
    p = subprocess.run(cmd, shell=True, text=True, capture_output=True)
    return [l.strip() for l in p.stdout.splitlines() if l.strip()] if p.returncode == 0 else []

local = run("git for-each-ref --format='%(refname:short)' refs/heads/")
remote = [r for r in run("git for-each-ref --format='%(refname:short)' refs/remotes/") if not r.endswith('/HEAD')]
prs = []
if subprocess.run("command -v gh >/dev/null 2>&1", shell=True).returncode == 0:
    prs = run("gh pr list --state open --json number,title,headRefName --jq '.[] | \"pr:\\\(.number)|\\\(.title)|\\\(.headRefName)\"'")

items = []
for b in local:
    items.append({"id": f"branch:{b}", "ref": b, "source": "local-branch"})
for b in remote:
    src = "github-branch" if b.startswith("origin/") else "remote-branch"
    items.append({"id": f"branch:{b}", "ref": b, "source": src})
for pr in prs:
    parts = pr.split("|", 2)
    if len(parts) == 3:
        pr_id, title, head = parts
        items.append({"id": pr_id, "ref": head, "title": title, "source": "pull-request"})

out = {"generated_on": __import__('datetime').date.today().isoformat(), "items": items}
path = ".ralph/agent/review-cycle/review-items.raw.json"
__import__('pathlib').Path(path).parent.mkdir(parents=True, exist_ok=True)
__import__('pathlib').Path(path).write_text(json.dumps(out, indent=2))
print(f"Wrote {path} ({len(items)} items)")
PY
