#!/usr/bin/env bash
# Sandboxed trace runner. Redirects TRACE_DIR/SIDECAR_DIR to /tmp so
# experiments on trace.sh (new bin rules, class-extraction changes, etc.)
# don't pollute production traces.
#
# Usage:
#   echo '<payload>' | bash scripts/trace-sandbox.sh post
#   echo '<payload>' | bash scripts/trace-sandbox.sh pre
#
# Output lands at /tmp/trace-sandbox/YYYY-MM-DD.jsonl. Inspect with:
#   cat /tmp/trace-sandbox/$(date -u +%F).jsonl | jq -c '{tool, class, bin}'
# Reset with:  rm -rf /tmp/trace-sandbox /tmp/trace-sandbox-sidecar

set -uo pipefail

export TRACE_DIR="/tmp/trace-sandbox"
export SIDECAR_DIR="/tmp/trace-sandbox-sidecar"

mkdir -p "$TRACE_DIR" "$SIDECAR_DIR"

exec bash /root/.openclaw/workspace/scripts/trace.sh "$@"
