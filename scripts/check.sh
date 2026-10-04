#!/usr/bin/env bash
# Every check CI runs, runnable before a push: ./scripts/check.sh
#   ./scripts/check.sh live [flags]   the live regression suite against a
#                                     scratch daemon (scripts/live-check.sh;
#                                     --copy-live adds a copy of this Mac's store)
set -euo pipefail
cd "$(dirname "$0")/.."
if [ "${1:-}" = "live" ]; then
  shift
  exec ./scripts/live-check.sh "$@"
fi
cargo test
