#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$ROOT_DIR/lib/voices/softcut_zig.lua"
HOST="${1:-norns.local}"
REMOTE_REPO_DIR="${2:-/home/we/dust/code/re_kriate}"
REMOTE_DEST="$REMOTE_REPO_DIR/lib/voices/softcut_zig.lua"

if [[ ! -f "$SRC" ]]; then
  echo "missing source file: $SRC" >&2
  exit 1
fi

scp "$SRC" "we@${HOST}:$REMOTE_DEST"
ssh "we@${HOST}" "test -f '$REMOTE_DEST' && echo 'installed softcut_zig to $REMOTE_DEST'"
