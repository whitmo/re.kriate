#!/usr/bin/env bash
set -euo pipefail

collect_local_branches() {
  git for-each-ref --format='%(refname:short)' refs/heads/
}

collect_remote_branches() {
  git for-each-ref --format='%(refname:short)' refs/remotes/ | sed '/\/HEAD$/d'
}

collect_github_branches() {
  collect_remote_branches | rg '^origin/' || true
}

collect_open_prs() {
  if command -v gh >/dev/null 2>&1; then
    gh pr list --state open --json number,title,headRefName --jq '.[] | "pr:\(.number)|\(.title)|\(.headRefName)"'
  else
    return 0
  fi
}
