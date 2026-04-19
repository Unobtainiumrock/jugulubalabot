#!/usr/bin/env bash
# Post-hoc token accounting from Claude Code transcripts.
# For the given date (default: today UTC), aggregates all assistant turns
# across all session files into workspace/turns/YYYY-MM-DD.jsonl with one
# row per turn: ts, session_id, turn_uuid, token counts, cost_cents, tools.
#
# Cost model defaults are Claude Opus 4.7 pricing (USD/MTok):
#   input $15, output $75, cache_creation (1h) $30, cache_read $1.50
# Claude Code uses 1h ephemeral cache by default for this project (see
# message.usage.cache_creation.ephemeral_1h_input_tokens in transcripts).
# For 5m cache workloads, set PRICE_CWRITE=0.001875.
# Override via env: PRICE_IN, PRICE_OUT, PRICE_CWRITE, PRICE_CREAD (cents/token).
#
# Usage:
#   bash scripts/token-accounting.sh                # today
#   bash scripts/token-accounting.sh 2026-04-19     # specific date

set -uo pipefail

WORKSPACE="/root/.openclaw/workspace"
PROJECT_DIR="/root/.claude/projects/-root--openclaw-workspace"
DATE="${1:-$(date -u +%F)}"
OUT_DIR="$WORKSPACE/turns"
OUT="$OUT_DIR/$DATE.jsonl"
mkdir -p "$OUT_DIR"

# Prices in cents per token (USD/MTok / 10000)
PRICE_IN="${PRICE_IN:-0.0015}"
PRICE_OUT="${PRICE_OUT:-0.0075}"
PRICE_CWRITE="${PRICE_CWRITE:-0.003}"
PRICE_CREAD="${PRICE_CREAD:-0.00015}"

# Temp accumulator
TMP=$(mktemp)
trap 'rm -f "$TMP"' EXIT

for sf in "$PROJECT_DIR"/*.jsonl; do
  [ -f "$sf" ] || continue
  jq -c --arg date "$DATE" --arg pin "$PRICE_IN" --arg pout "$PRICE_OUT" \
        --arg pcw "$PRICE_CWRITE" --arg pcr "$PRICE_CREAD" '
    select(.type == "assistant" and .message.usage)
    | select(.timestamp | startswith($date))
    | (.message.usage.input_tokens // 0) as $in
    | (.message.usage.output_tokens // 0) as $out
    | (.message.usage.cache_creation_input_tokens // 0) as $cw
    | (.message.usage.cache_read_input_tokens // 0) as $cr
    | ([.message.content[]? | select(.type == "tool_use") | .name] // []) as $tools
    | {
        ts: .timestamp,
        session_id: .sessionId,
        turn_uuid: .uuid,
        input_tokens: $in,
        output_tokens: $out,
        cache_write_tokens: $cw,
        cache_read_tokens: $cr,
        cost_cents: (($in * ($pin | tonumber)) + ($out * ($pout | tonumber)) + ($cw * ($pcw | tonumber)) + ($cr * ($pcr | tonumber))),
        tools: $tools
      }
  ' "$sf" 2>/dev/null >> "$TMP" || true
done

# Sort by timestamp
sort "$TMP" > "$OUT"
rm -f "$TMP"
trap - EXIT

TOTAL_TURNS=$(wc -l < "$OUT" | tr -d ' ')
if [ "$TOTAL_TURNS" -eq 0 ]; then
  echo "No assistant turns found for $DATE"
  exit 0
fi

# Aggregate stats
jq -s '
  {
    turns: length,
    input_tokens:  (map(.input_tokens)  | add),
    output_tokens: (map(.output_tokens) | add),
    cache_write:   (map(.cache_write_tokens) | add),
    cache_read:    (map(.cache_read_tokens)  | add),
    cost_cents:    (map(.cost_cents) | add),
    sessions:      (map(.session_id) | unique | length)
  }
' "$OUT" | jq '. + {cost_usd: (.cost_cents / 100)}'

echo "Wrote $OUT"
