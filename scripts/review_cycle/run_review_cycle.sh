#!/usr/bin/env bash
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

scripts/review_cycle/collect_review_items.sh
scripts/review_cycle/classify_review_items.sh
scripts/review_cycle/generate_review_cycle_json.sh
scripts/review_cycle/render_review_lists.sh
scripts/review_cycle/generate_task_candidates.sh
scripts/review_cycle/render_simplicity_plan.sh
scripts/review_cycle/check_milestone.sh && {
  scripts/review_cycle/update_code_review_doc.sh
  scripts/review_cycle/render_gap_mapping.sh
  scripts/review_cycle/update_branch_gap_doc.sh
}
scripts/review_cycle/validate_contracts.sh
