#!/usr/bin/env bash
# Run tests with coverage and generate a report.
# Usage: ./scripts/coverage.sh [--summary] [--check THRESHOLD]
#
# --summary   Print only the summary table (no per-line annotations)
# --check N   Exit non-zero if total coverage < N% (default: no threshold)

set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

SUMMARY_ONLY=false
THRESHOLD=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --summary) SUMMARY_ONLY=true; shift ;;
    --check)   THRESHOLD="$2"; shift 2 ;;
    *)         echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

# Clean previous run
rm -f luacov.stats.out luacov.report.out

# Run tests with coverage
busted --coverage specs/

# Generate report
luacov

if [[ "$SUMMARY_ONLY" == "true" ]]; then
  # Print from "Summary" header to end of file
  sed -n '/^Summary$/,$p' luacov.report.out
else
  cat luacov.report.out
fi

# Threshold check
if [[ -n "$THRESHOLD" ]]; then
  TOTAL=$(grep '^Total' luacov.report.out | awk '{print $NF}' | tr -d '%')
  if (( $(echo "$TOTAL < $THRESHOLD" | bc -l) )); then
    echo ""
    echo "FAIL: Coverage ${TOTAL}% is below threshold ${THRESHOLD}%"
    exit 1
  else
    echo ""
    echo "OK: Coverage ${TOTAL}% meets threshold ${THRESHOLD}%"
  fi
fi
