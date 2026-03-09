#!/usr/bin/env bash
set -euo pipefail

speak_text() {
  local text="$1"
  local voice="${2:-}"
  if command -v say >/dev/null 2>&1; then
    if [ -n "$voice" ]; then
      say -v "$voice" "$text" || say "$text"
    else
      say "$text"
    fi
  else
    printf 'SPEAK: %s\n' "$text"
  fi
}
