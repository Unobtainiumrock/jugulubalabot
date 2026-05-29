#!/usr/bin/env bash
# Best-effort, post-turn cost-budget peek. The number lags the running
# session by ~1 turn: the harness writes transcript records only after a
# turn closes, so the in-flight turn is invisible until the next refresh.
# Forces a fresh token-accounting pass first so the lag is bounded by
# transcript-write cadence, not by nightly close — but it is never zero.
# Use the output as guidance ("am I burning cash?"), not enforcement of
# the turn you are in right now.
#
# Usage:
#   bash scripts/budget-peek.sh                 # latest session in today's turns
#   bash scripts/budget-peek.sh <prefix>        # specific session by id prefix
#   bash scripts/budget-peek.sh --all           # sum across all sessions today
#   bash scripts/budget-peek.sh --risk          # compaction-risk estimate
#   bash scripts/budget-peek.sh --live          # latest session + LIVE/WARM/STALE freshness label and lag (label, not a freshness claim)
set -uo pipefail

WORKSPACE="/root/.openclaw/workspace"
DATE="$(date -u +%F)"
TURNS="$WORKSPACE/turns/$DATE.jsonl"
PROJECT_DIR="/root/.claude/projects/-root--openclaw-workspace"

# Refresh from transcripts so the peek is fresh, not stuck at last nightly.
if [ -d "/root/.claude/projects/-root--openclaw-workspace" ]; then
  bash "$WORKSPACE/scripts/token-accounting.sh" "$DATE" >/dev/null 2>&1 || true
fi

if [ ! -f "$TURNS" ] || [ ! -s "$TURNS" ]; then
  echo "budget-peek: no turns for $DATE yet"
  exit 0
fi

MODE="${1:-}"

age_human() {
  local seconds="$1"
  if [ "$seconds" -lt 60 ]; then
    printf '%ss' "$seconds"
  elif [ "$seconds" -lt 3600 ]; then
    printf '%sm%ss' $((seconds / 60)) $((seconds % 60))
  else
    printf '%sh%sm' $((seconds / 3600)) $(((seconds % 3600) / 60))
  fi
}

freshness_line() {
  local session="$1"
  local latest_ts
  latest_ts=$(jq -s -r --arg s "$session" 'map(select(.session_id == $s)) | sort_by(.ts) | last | .ts' "$TURNS")
  local latest_epoch now lag_sec transcript age_sec state note
  latest_epoch=$(date -u -d "$latest_ts" +%s 2>/dev/null || echo 0)
  now=$(date -u +%s)
  lag_sec=$((now - latest_epoch))
  transcript="$PROJECT_DIR/$session.jsonl"
  if [ -f "$transcript" ]; then
    age_sec=$((now - $(stat -c %Y "$transcript" 2>/dev/null || echo "$now")))
  else
    age_sec=-1
  fi
  if [ "$lag_sec" -lt 120 ] && { [ "$age_sec" -lt 0 ] || [ "$age_sec" -lt 120 ]; }; then
    state="LIVE"
    note="transcript and turns look current"
  elif [ "$lag_sec" -lt 900 ] && { [ "$age_sec" -lt 0 ] || [ "$age_sec" -lt 900 ]; }; then
    state="WARM"
    note="fresh enough for guidance, not enforcement"
  else
    state="STALE"
    note="turn data may lag the active session"
  fi
  if [ "$age_sec" -ge 0 ]; then
    printf 'Freshness [%s] — latest accounted turn %s ago · transcript touched %s ago · %s\n' \
      "$state" "$(age_human "$lag_sec")" "$(age_human "$age_sec")" "$note"
  else
    printf 'Freshness [%s] — latest accounted turn %s ago · transcript file missing · %s\n' \
      "$state" "$(age_human "$lag_sec")" "$note"
  fi
}

if [ "$MODE" = "--risk" ]; then
  # Compaction-risk: context size ≈ cache_read + cache_write + input
  # from the latest turn (the rolling window sent to the model).
  # Compaction typically triggers ~180-200k on default autoCompactWindow.
  SESSION=$(jq -s -r 'sort_by(.ts) | last | .session_id' "$TURNS")
  jq -s -r --arg s "$SESSION" '
    map(select(.session_id == $s))
    | sort_by(.ts) as $all
    | ($all | last) as $latest
    | (($latest.cache_read_tokens // 0) + ($latest.cache_write_tokens // 0) + ($latest.input_tokens // 0)) as $ctx
    | (if $ctx < 100000 then "GREEN"
        elif $ctx < 150000 then "YELLOW"
        elif $ctx < 180000 then "ORANGE"
        else "RED" end) as $status
    | (if $ctx < 100000 then "plenty of headroom"
        elif $ctx < 150000 then "watch it — consider saving working state to state/scratch.md"
        elif $ctx < 180000 then "save state now, wrap the current task, expect compaction soon"
        else "compaction likely imminent — write state/scratch.md and finish whatever turn is mid-flight" end) as $advice
    | "Context-risk [\($status)] — session \($s[0:8]) · ctx ≈ \($ctx) tok (cache_read \($latest.cache_read_tokens) + cache_write \($latest.cache_write_tokens) + input \($latest.input_tokens))
\($advice)"
  ' "$TURNS"
  exit 0
fi

if [ "$MODE" = "--live" ]; then
  SESSION=$(jq -s -r 'sort_by(.ts) | last | .session_id' "$TURNS")
  jq -s -r --arg s "$SESSION" '
    map(select(.session_id == $s))
    | sort_by(.ts) as $all
    | ($all | length) as $n
    | (($all | map(.cost_cents) | add) / 100) as $cost
    | ($all | last) as $latest
    | ($all | map(.input_tokens) | add) as $in
    | ($all | map(.output_tokens) | add) as $out
    | (($latest.cache_read_tokens // 0) + ($latest.cache_write_tokens // 0) + ($latest.input_tokens // 0)) as $ctx
    | (if $ctx < 100000 then "GREEN"
        elif $ctx < 150000 then "YELLOW"
        elif $ctx < 180000 then "ORANGE"
        else "RED" end) as $status
    | "Live session \($s[0:8]) · \($n) turns · $\($cost | . * 100 | round / 100)
\($in) in / \($out) out · latest turn \($latest.ts | split("T")[1] | split(".")[0])Z
Context-risk [\($status)] · ctx ≈ \($ctx) tok (cache_read \($latest.cache_read_tokens) + cache_write \($latest.cache_write_tokens) + input \($latest.input_tokens))"
  ' "$TURNS"
  freshness_line "$SESSION"
  exit 0
fi

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
