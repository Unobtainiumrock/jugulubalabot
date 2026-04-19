#!/usr/bin/env bash
# Summarize a single Claude Code session: turn count, tool usage, cost, and
# first + last user messages (to recover what the session was about).
#
# Usage:
#   scripts/session-summary.sh <session-uuid-or-prefix>
#   scripts/session-summary.sh latest                   # most recently modified
#
# Session files live at /root/.claude/projects/-root--openclaw-workspace/*.jsonl

set -uo pipefail

PROJECT_DIR="/root/.claude/projects/-root--openclaw-workspace"
ARG="${1:-latest}"

if [ "$ARG" = "latest" ]; then
  SF=$(ls -t "$PROJECT_DIR"/*.jsonl 2>/dev/null | head -1)
else
  # Match by prefix (full or short uuid)
  SF=$(ls "$PROJECT_DIR"/"$ARG"*.jsonl 2>/dev/null | head -1)
fi

if [ -z "$SF" ] || [ ! -f "$SF" ]; then
  echo "No session file found for '$ARG'" >&2
  exit 1
fi

SID=$(basename "$SF" .jsonl)
FIRST_TS=$(jq -r '.timestamp // empty' "$SF" | head -1)
LAST_TS=$(jq -r '.timestamp // empty' "$SF" | tail -1)
USER_TURNS=$(jq -r 'select(.type == "user") | 1' "$SF" | wc -l | tr -d ' ')
ASSISTANT_TURNS=$(jq -r 'select(.type == "assistant") | 1' "$SF" | wc -l | tr -d ' ')

# First + last user message
FIRST_USER=$(jq -r 'select(.type == "user") | .message.content // "" | tostring' "$SF" | head -1 | cut -c1-200)
LAST_USER=$(jq -r 'select(.type == "user") | .message.content // "" | tostring' "$SF" | tail -1 | cut -c1-200)

# Tool usage breakdown
TOOLS=$(jq -r 'select(.type == "assistant")
  | .message.content // []
  | .[]? | select(.type == "tool_use") | .name' "$SF" 2>/dev/null \
  | sort | uniq -c | sort -rn \
  | awk '{printf "  %-20s %5d\n", $2, $1}')

# Cost (if matching turns rows exist)
TURN_DATE=$(echo "$FIRST_TS" | cut -c1-10)
TURNS_FILE="/root/.openclaw/workspace/turns/$TURN_DATE.jsonl"
COST="n/a (run token-accounting.sh $TURN_DATE first)"
if [ -f "$TURNS_FILE" ]; then
  COST=$(jq -s --arg sid "$SID" '
    map(select(.session_id == $sid))
    | {turns: length, cost_usd: ((map(.cost_cents) | add) / 100), in_tokens: (map(.input_tokens) | add), out_tokens: (map(.output_tokens) | add)}
    | "turns=\(.turns) cost=$\(.cost_usd | . * 100 | round / 100) in=\(.in_tokens) out=\(.out_tokens)"
  ' "$TURNS_FILE" -r 2>/dev/null || echo "n/a")
fi

cat <<EOF
=== Session $SID ===
File:        $SF
Started:     $FIRST_TS
Ended:       $LAST_TS
User turns:  $USER_TURNS
Asst turns:  $ASSISTANT_TURNS
Cost:        $COST

First user message:
  $FIRST_USER

Last user message:
  $LAST_USER

Tool usage:
$TOOLS
EOF
