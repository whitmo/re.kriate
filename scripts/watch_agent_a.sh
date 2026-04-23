#!/usr/bin/env bash
set -euo pipefail

# Poll .ralph/agent/scratchpad.md for changes and invoke a configured agent command
# when a new note addressed to `agent-a` appears.
#
# Usage:
#   AGENT_CMD='pi --prompt' scripts/watch_agent_a.sh
#   AGENT_CMD='your-agent-cli run' POLL_SECONDS=10 scripts/watch_agent_a.sh
#
# Required:
#   AGENT_CMD  Command prefix used to invoke the agent.
#              It must accept a single prompt string as its final argument.
#
# Optional:
#   SCRATCHPAD=.ralph/agent/scratchpad.md
#   STATE_DIR=.ralph/agent/.watch
#   POLL_SECONDS=15
#   DRY_RUN=0                    # 1 = log prompts, do not invoke agent
#   APPEND_RECEIPT=1             # 1 = append handled receipt to scratchpad

SCRATCHPAD="${SCRATCHPAD:-.ralph/agent/scratchpad.md}"
STATE_DIR="${STATE_DIR:-.ralph/agent/.watch}"
POLL_SECONDS="${POLL_SECONDS:-15}"
DRY_RUN="${DRY_RUN:-0}"
APPEND_RECEIPT="${APPEND_RECEIPT:-1}"
STATE_FILE="$STATE_DIR/agent-a.last_line"
LOG_FILE="$STATE_DIR/agent-a-watch.log"

mkdir -p "$STATE_DIR"

touch "$LOG_FILE"

if [[ ! -f "$SCRATCHPAD" ]]; then
  echo "scratchpad not found: $SCRATCHPAD" >&2
  exit 1
fi

if [[ -z "${AGENT_CMD:-}" ]]; then
  cat >&2 <<'EOF'
AGENT_CMD is required.

Example:
  AGENT_CMD='pi --prompt' scripts/watch_agent_a.sh

The command must accept one prompt string as its final argument.
EOF
  exit 1
fi

if [[ ! -f "$STATE_FILE" ]]; then
  printf '0\n' > "$STATE_FILE"
fi

log() {
  printf '[%s] %s\n' "$(date -u +'%Y-%m-%dT%H:%M:%SZ')" "$*" | tee -a "$LOG_FILE"
}

append_receipt() {
  local status="$1"
  local detail="$2"

  if [[ "$APPEND_RECEIPT" != "1" ]]; then
    return 0
  fi

  cat >> "$SCRATCHPAD" <<EOF

## $(date -u +'%Y-%m-%d %H:%M UTC') — watcher
To: agent-a
Status: $status
Context: $detail
Claimed: n/a
EOF
}

invoke_agent() {
  local new_text="$1"
  local prompt
  prompt=$(cat <<EOF
You are agent-a working in repo $(pwd) on branch $(git branch --show-current 2>/dev/null || echo unknown).

Read and act on the new scratchpad message(s) for agent-a below. If action is needed:
1. inspect any referenced files
2. make only the requested safe changes
3. append a concise handoff back to .ralph/agent/scratchpad.md
4. keep coordination within .ralph/agent/ unless explicitly asked otherwise

New scratchpad content:
$new_text
EOF
)

  if [[ "$DRY_RUN" == "1" ]]; then
    log "dry-run: would invoke agent with prompt below"
    {
      printf '----- PROMPT BEGIN -----\n'
      printf '%s\n' "$prompt"
      printf '----- PROMPT END -----\n'
    } >> "$LOG_FILE"
    append_receipt "dry-run" "watcher detected a new message for agent-a but did not invoke the agent (DRY_RUN=1)."
    return 0
  fi

  log "invoking agent"
  append_receipt "received" "watcher detected a new message for agent-a and is invoking the agent command."
  # shellcheck disable=SC2086
  if eval "$AGENT_CMD" "\"$prompt\"" >> "$LOG_FILE" 2>&1; then
    append_receipt "handled" "watcher invoked the agent command successfully; see .ralph/agent/.watch/agent-a-watch.log for details."
  else
    log "agent command exited non-zero"
    append_receipt "error" "watcher invoked the agent command but it exited non-zero; see .ralph/agent/.watch/agent-a-watch.log."
  fi
}

extract_new_agent_messages() {
  local start_line="$1"
  awk -v start="$start_line" 'NR > start { print }' "$SCRATCHPAD" | awk '
    BEGIN { capture=0; block="" }
    /^## / {
      if (capture && block != "") {
        printf "%s\n---BLOCK---\n", block
      }
      block=$0 "\n"
      capture=0
      next
    }
    {
      block = block $0 "\n"
      if ($0 ~ /To:[[:space:]]*agent-a/) capture=1
    }
    END {
      if (capture && block != "") printf "%s\n", block
    }
  '
}

log "watching $SCRATCHPAD every ${POLL_SECONDS}s"

while true; do
  current_lines=$(wc -l < "$SCRATCHPAD" | tr -d ' ')
  last_line=$(cat "$STATE_FILE")

  if (( current_lines > last_line )); then
    new_blocks=$(extract_new_agent_messages "$last_line")
    printf '%s\n' "$current_lines" > "$STATE_FILE"

    if [[ -n "$new_blocks" ]]; then
      log "detected new message(s) to agent-a"
      invoke_agent "$new_blocks"
    else
      log "scratchpad changed, but no new To: agent-a blocks found"
    fi
  fi

  sleep "$POLL_SECONDS"
done
