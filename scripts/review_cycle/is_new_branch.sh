#!/usr/bin/env bash
set -euo pipefail

branch="${1:?branch required}"
ledger=".ralph/agent/review-cycle/new-branch-ledger.txt"
mkdir -p .ralph/agent/review-cycle
if [ -f "$ledger" ] && rg -qxF "$branch" "$ledger"; then
  echo "false"
else
  printf '%s\n' "$branch" >> "$ledger"
  echo "true"
fi
