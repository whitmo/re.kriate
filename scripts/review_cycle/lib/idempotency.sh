#!/usr/bin/env bash
set -euo pipefail

LEDGER_DEFAULT=".ralph/agent/review-cycle/idempotency-ledger.txt"

idempotency_seen() {
  local key="$1"
  local ledger="${2:-$LEDGER_DEFAULT}"
  [ -f "$ledger" ] && rg -qxF "$key" "$ledger"
}

idempotency_record() {
  local key="$1"
  local ledger="${2:-$LEDGER_DEFAULT}"
  mkdir -p "$(dirname "$ledger")"
  touch "$ledger"
  if ! idempotency_seen "$key" "$ledger"; then
    printf '%s\n' "$key" >> "$ledger"
  fi
}
