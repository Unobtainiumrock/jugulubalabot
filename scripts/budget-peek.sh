#!/usr/bin/env bash
# Live cost-budget peek for the current day's turns. Forces a fresh
# token-accounting pass first so the numbers reflect recent transcript
# writes, not just what was captured at nightly close.
#
# Usage:
#   bash scripts/budget-peek.sh                 # latest session in today's turns
#   bash scripts/budget-peek.sh <prefix>        # specific session by id prefix
#   bash scripts/budget-peek.sh --all           # sum across all sessions today
set -uo pipefail

WORKSPACE="/root/.openclaw/workspace"
DATE="$(date -u +%F)"
TURNS="$WORKSPACE/turns/$DATE.jsonl"

# Refresh from transcripts so the peek is fresh, not stuck at last nightly.
if [ -d "/root/.claude/projects/-root--openclaw-workspace" ]; then
  bash "$WORKSPACE/scripts/token-accounting.sh" "$DATE" >/dev/null 2>&1 || true
fi

if [ ! -f "$TURNS" ] || [ ! -s "$TURNS" ]; then
  echo "budget-peek: no turns for $DATE yet"
  exit 0
fi

MODE="${1:-}"

if [ "$MODE" = "--all" ]; then
  jq -s -r '
    sort_by(.ts) as $all
    | {
        date: "'"$DATE"'",
        sessions: ($all | map(.session_id) | unique | length),
        turns: ($all | length),
        cost_usd: (($all | map(.cost_cents) | add) / 100),
        in_tok: ($all | map(.input_tokens) | add),
        out_tok: ($all | map(.output_tokens) | add),
        first_ts: ($all | first | .ts),
        last_ts: ($all | last | .ts)
      }
    | "All sessions \(.date) · \(.sessions) sessions · \(.turns) turns · $\(.cost_usd | . * 100 | round / 100)
\(.in_tok) in / \(.out_tok) out · \(.first_ts | split("T")[1] | split(".")[0])Z → \(.last_ts | split("T")[1] | split(".")[0])Z"
  ' "$TURNS"
  exit 0
fi

# Pick session
if [ -n "$MODE" ]; then
  SESSION=$(jq -r '.session_id' "$TURNS" | sort -u | grep -m1 "^$MODE" || true)
  if [ -z "$SESSION" ]; then
    echo "budget-peek: no session starting with '$MODE'" >&2
    exit 1
  fi
else
  SESSION=$(jq -s -r 'sort_by(.ts) | last | .session_id' "$TURNS")
fi

jq -s -r --arg s "$SESSION" '
  map(select(.session_id == $s))
  | sort_by(.ts) as $all
  | ($all | length) as $n
  | (($all | map(.cost_cents) | add) / 100) as $cost
  | {
      session: ($s[0:8]),
      turns: $n,
      cost_usd: $cost,
      in_tok: ($all | map(.input_tokens) | add),
      out_tok: ($all | map(.output_tokens) | add),
      first_ts: ($all | first | .ts),
      last_ts: ($all | last | .ts)
    }
  | "Session \(.session) · \(.turns) turns · $\(.cost_usd | . * 100 | round / 100)
\(.in_tok) in / \(.out_tok) out · \(.first_ts | split("T")[1] | split(".")[0])Z → \(.last_ts | split("T")[1] | split(".")[0])Z"
' "$TURNS"
