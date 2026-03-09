#!/usr/bin/env bash
set -euo pipefail

origin_group_for_ref() {
  local ref="$1"
  if echo "$ref" | rg -q 'multiclaude'; then
    echo "multiclaude"
  elif echo "$ref" | rg -q '^origin/'; then
    echo "core"
  else
    echo "other"
  fi
}
