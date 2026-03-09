#!/usr/bin/env bash
set -euo pipefail

classify_branch_status() {
  local name="$1"
  if echo "$name" | rg -qi '(wip|draft|spike|hold|blocked)'; then
    echo "wait"
  else
    echo "merge-now"
  fi
}

risk_level_for_item() {
  local name="$1"
  if echo "$name" | rg -qi '(hotfix|security|auth|payment)'; then
    echo "high"
  elif echo "$name" | rg -qi '(refactor|cleanup|docs)'; then
    echo "low"
  else
    echo "medium"
  fi
}
