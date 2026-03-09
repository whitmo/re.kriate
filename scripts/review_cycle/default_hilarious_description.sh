#!/usr/bin/env bash
set -euo pipefail
seed="${1:-default}"
case "$(( $(printf '%s' "$seed" | cksum | awk '{print $1}') % 4 ))" in
  0) echo "heroically wrangled gremlins" ;;
  1) echo "performed jazz hands on bugs" ;;
  2) echo "dropkicked chaos into orbit" ;;
  *) echo "made the compiler clap" ;;
esac
