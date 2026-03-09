#!/usr/bin/env bash
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

rg -q "REVIEW-CYCLE-SIMPLICITY-START" docs/code-review.html
rg -q "REVIEW-CYCLE-GAPS-START" docs/branch-gap-analysis.html
echo "US3 validation passed: canonical docs synchronized"
