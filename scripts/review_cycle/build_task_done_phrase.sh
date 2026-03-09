#!/usr/bin/env bash
set -euo pipefail
if [ "$#" -lt 1 ]; then
  echo "usage: $0 <task_number> [description]" >&2
  exit 1
fi
task_number="$1"
desc="${2:-}"
if [ -z "$desc" ]; then
  desc="$(scripts/review_cycle/default_hilarious_description.sh "$task_number")"
fi
printf 'DONE %s %s\n' "$task_number" "$desc"
