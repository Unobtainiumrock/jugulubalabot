#!/usr/bin/env bash
# Append a single round to state/peer-loop/rounds.jsonl. Called by send.sh
# and recv.sh. Schema-agnostic: writes whatever fields the caller passes via
# environment vars. Missing fields default to null / 0.
#
# Usage:
#   ROUND_DIR=sent ROUND_NUM=7 ROUND_CORR=ab12cd34 ROUND_REPLY_TO=ef56gh78 \
#   ROUND_BODY_CHARS=1247 ROUND_DUR_MS=3210 ROUND_HALT=false \
#   bash peer-agent/bin/round-log.sh
set -uo pipefail
STATE="/root/.openclaw/workspace/state/peer-loop"
mkdir -p "$STATE"
TS=$(date -u +%Y-%m-%dT%H:%M:%S.%3NZ)
jq -cn \
  --arg ts "$TS" \
  --arg dir "${ROUND_DIR:-unknown}" \
  --argjson round "${ROUND_NUM:-0}" \
  --arg corr "${ROUND_CORR:-}" \
  --arg reply_to "${ROUND_REPLY_TO:-}" \
  --argjson body_chars "${ROUND_BODY_CHARS:-0}" \
  --argjson duration_ms "${ROUND_DUR_MS:-0}" \
  --argjson halt "${ROUND_HALT:-false}" \
  '{ts:$ts, round:$round, direction:$dir, correlation_id:$corr,
    in_reply_to:(if $reply_to=="" then null else $reply_to end),
    body_chars:$body_chars, duration_ms:$duration_ms, halt_request:$halt}' \
  >> "$STATE/rounds.jsonl"
