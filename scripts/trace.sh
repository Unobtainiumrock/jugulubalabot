#!/usr/bin/env bash
# Phase 2 trace writer. One JSONL line per tool call.
# Invoked by hooks with first arg "pre" | "ok" | "fail".
#   pre  -> record start timestamp (sidecar file)
#   ok   -> PostToolUse: consume sidecar, compute duration, append success
#   fail -> PostToolUseFailure: same but success=false
set -euo pipefail

MODE="${1:-ok}"
TRACE_DIR="/root/.openclaw/workspace/traces"
SIDECAR_DIR="/root/.openclaw/workspace/state/trace-inflight"
mkdir -p "$TRACE_DIR" "$SIDECAR_DIR"

PAYLOAD=$(cat)
TOOL=$(printf '%s' "$PAYLOAD" | jq -r '.tool_name // "unknown"')
SESSION=$(printf '%s' "$PAYLOAD" | jq -r '.session_id // "unknown"')
INPUT_HASH=$(printf '%s' "$PAYLOAD" | jq -cS '.tool_input // {}' | sha256sum | cut -c1-12)
KEY="${SESSION}__${TOOL}__${INPUT_HASH}"
SIDECAR="$SIDECAR_DIR/$KEY"

# Nanosecond epoch for duration math
NOW_NS=$(date -u +%s%N)

if [ "$MODE" = "pre" ]; then
  printf '%s\n' "$NOW_NS" > "$SIDECAR"
  exit 0
fi

SUCCESS="true"
[ "$MODE" = "fail" ] && SUCCESS="false"

DURATION_MS="null"
if [ -f "$SIDECAR" ]; then
  START_NS=$(cat "$SIDECAR" 2>/dev/null || echo "")
  rm -f "$SIDECAR"
  if [ -n "$START_NS" ]; then
    DURATION_MS=$(( (NOW_NS - START_NS) / 1000000 ))
  fi
fi

# Rough input-shape class: a short string pulled from the tool-specific field
# most useful for binning. Kept cheap; the nightly reflection can re-class.
CLASS=$(printf '%s' "$PAYLOAD" | jq -r '
  def head: split(" ")[0] // "";
  def ext: capture("\\.(?<e>[A-Za-z0-9]+)$").e // "";
  .tool_input as $i |
  if   .tool_name == "Bash"                      then ($i.command // "" | head)
  elif .tool_name == "Skill"                     then ($i.skill // "")
  elif .tool_name == "Agent" or .tool_name == "Task" then ($i.subagent_type // "general-purpose")
  elif .tool_name == "Read" or .tool_name == "Write" or .tool_name == "Edit"
       then ($i.file_path // "" | ext)
  elif .tool_name == "Glob"                      then ($i.pattern // "")
  elif .tool_name == "Grep"                      then (if ($i.pattern // "" | length) < 20 then "simple" else "complex" end)
  elif .tool_name == "WebFetch" or .tool_name == "WebSearch" then "external"
  else ""
  end' 2>/dev/null || echo "")

TS=$(date -u +%Y-%m-%dT%H:%M:%S.%3NZ)
DATE=$(date -u +%Y-%m-%d)
OUT="$TRACE_DIR/$DATE.jsonl"

jq -cn \
  --arg ts "$TS" \
  --arg session "$SESSION" \
  --arg tool "$TOOL" \
  --arg hash "$INPUT_HASH" \
  --arg class "$CLASS" \
  --argjson success "$SUCCESS" \
  --argjson duration_ms "$DURATION_MS" \
  '{ts: $ts, session_id: $session, tool: $tool, class: $class, input_hash: $hash, success: $success, duration_ms: $duration_ms, bin: null}' \
  >> "$OUT"
