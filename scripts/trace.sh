#!/usr/bin/env bash
# Phase 2 trace writer. One JSONL line per tool call.
# Invoked by hooks with first arg "pre" | "post".
#   pre   -> record start timestamp (sidecar file)
#   post  -> consume sidecar, compute duration, read success from payload
set -euo pipefail

MODE="${1:-post}"
# Paths overridable via env for sandbox/test runs (see scripts/trace-sandbox.sh).
TRACE_DIR="${TRACE_DIR:-/root/.openclaw/workspace/traces}"
SIDECAR_DIR="${SIDECAR_DIR:-/root/.openclaw/workspace/state/trace-inflight}"
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

# PostToolUse payload carries tool_response; treat explicit is_error/error as failure
SUCCESS=$(printf '%s' "$PAYLOAD" | jq -r '
  if (.tool_response.is_error // false) == true then "false"
  elif (.tool_response.error // null) != null then "false"
  else "true" end' 2>/dev/null || echo "true")

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

# Semantic bin — coarse intent bucket. Classifier is deliberately small; edge
# cases fall through to "exec" or "other" and are surfaced by bin-sanity.sh.
BIN=$(printf '%s' "$PAYLOAD" | jq -r '
  .tool_name as $t |
  .tool_input as $i |
  ($i.command // "") as $cmd |
  ($i.file_path // "") as $path |
  if   $t == "Read" or $t == "Grep" or $t == "Glob" or $t == "ToolSearch" then "file_ground"
  elif $t == "Write" or $t == "Edit" or $t == "NotebookEdit" then
    (if ($path | test("/memory/")) then "memory_update" else "self_modify" end)
  elif $t == "Agent" or $t == "Task" then "agent_spawn"
  elif $t == "Skill" then
    (if ($i.skill // "") == "schedule" or ($i.skill // "") == "loop" then "scheduling" else "exec" end)
  elif $t == "WebFetch" or $t == "WebSearch" then "external_fetch"
  elif $t == "Bash" then
    (if   ($cmd | test("openclaw +message"))                     then "comms"
     elif ($cmd | test("openclaw +(cron|schedule)"))              then "scheduling"
     elif ($cmd | test("openclaw +(devices|doctor|sessions)"))    then "external_fetch"
     elif ($cmd | test("^(curl|wget|ssh|scp|rsync)\\b"))          then "external_fetch"
     else "exec" end)
  elif $t == "mcp__openclaw__cron" then "scheduling"
  elif $t == "mcp__openclaw__sessions_send" or $t == "mcp__openclaw__sessions_yield" then "comms"
  elif $t == "mcp__openclaw__sessions_spawn" or $t == "mcp__openclaw__subagents" then "agent_spawn"
  elif $t == "mcp__openclaw__memory_get" or $t == "mcp__openclaw__memory_search" or $t == "mcp__openclaw__sessions_list" or $t == "mcp__openclaw__sessions_history" or $t == "mcp__openclaw__session_status" then "file_ground"
  elif ($t | startswith("mcp__openclaw__")) then "external_fetch"
  else "other"
  end' 2>/dev/null || echo "other")

TS=$(date -u +%Y-%m-%dT%H:%M:%S.%3NZ)
DATE=$(date -u +%Y-%m-%d)
OUT="$TRACE_DIR/$DATE.jsonl"

jq -cn \
  --arg ts "$TS" \
  --arg session "$SESSION" \
  --arg tool "$TOOL" \
  --arg hash "$INPUT_HASH" \
  --arg class "$CLASS" \
  --arg bin "$BIN" \
  --argjson success "$SUCCESS" \
  --argjson duration_ms "$DURATION_MS" \
  '{ts: $ts, session_id: $session, tool: $tool, class: $class, input_hash: $hash, success: $success, duration_ms: $duration_ms, bin: $bin}' \
  >> "$OUT"
