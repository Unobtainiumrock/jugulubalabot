#!/usr/bin/env bash
# Queue an outgoing message for the peer agent.
# Usage:
#   peer-agent/bin/send.sh <file>   # read body from file
#   peer-agent/bin/send.sh -        # read body from stdin
set -euo pipefail
LANE="/root/.openclaw/workspace/peer-agent"
TS=$(date -u +%Y-%m-%dT%H:%M:%S.%3NZ)
SLUG=$(date -u +%Y-%m-%d-%H%M%S)
OUT="$LANE/outbox/${SLUG}.txt"
mkdir -p "$LANE/outbox"
if [ "${1:-}" = "-" ] || [ -z "${1:-}" ]; then
  cat > "$OUT"
else
  cp -- "$1" "$OUT"
fi
BODY=$(cat "$OUT")
jq -cn --arg ts "$TS" --arg dir "sent" --arg body "$BODY" --arg path "$OUT" \
  '{ts:$ts, direction:$dir, body:$body, file:$path}' >> "$LANE/transcript.jsonl"
echo "$OUT"
