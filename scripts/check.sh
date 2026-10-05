#!/usr/bin/env bash
# Every check CI runs, runnable before a push: ./scripts/check.sh
#   ./scripts/check.sh live [flags]   the live regression suite against a
#                                     scratch daemon (scripts/live-check.sh;
#                                     --copy-live adds a copy of this Mac's store)
#   ./scripts/check.sh eval [flags]   the linggen plugin's `claude plugin eval`
#                                     suite (scripts/plugin-eval.sh) — calls a
#                                     real model, so never part of the default
set -euo pipefail
cd "$(dirname "$0")/.."
if [ "${1:-}" = "live" ]; then
  shift
  exec ./scripts/live-check.sh "$@"
fi
if [ "${1:-}" = "eval" ]; then
  shift
  exec ./scripts/plugin-eval.sh "$@"
fi
cargo test
