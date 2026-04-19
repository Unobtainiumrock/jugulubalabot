#!/usr/bin/env bash
# Search across all Claude Code transcripts on this VPS. Lets Tai look at
# what was said/done in any prior session — the only persistent record of
# conversation content beyond the memory system.
#
# Usage:
#   scripts/session-search.sh "pattern"            # case-insensitive regex
#   scripts/session-search.sh "pattern" --since 2026-04-19
#
# Output: one line per match — <date> <session-8> <role> <text snippet>

set -uo pipefail

PROJECT_DIR="/root/.claude/projects/-root--openclaw-workspace"
PATTERN="${1:-}"
if [ -z "$PATTERN" ]; then
  echo "Usage: $(basename "$0") \"pattern\" [--since YYYY-MM-DD]" >&2
  exit 2
fi
shift || true

SINCE=""
while [ $# -gt 0 ]; do
  case "$1" in
    --since) SINCE="$2"; shift 2 ;;
    *) echo "Unknown flag: $1" >&2; exit 2 ;;
  esac
done

for sf in "$PROJECT_DIR"/*.jsonl; do
  [ -f "$sf" ] || continue
  SID=$(basename "$sf" .jsonl | cut -c1-8)
  jq -r --arg pat "$PATTERN" --arg since "$SINCE" --arg sid "$SID" '
    select(.timestamp)
    | select(($since | length) == 0 or (.timestamp >= $since))
    | select(.type == "user" or .type == "assistant")
    | (.timestamp | split("T")[0]) as $date
    | .type as $role
    | (
        if .type == "user" then (.message.content // "" | tostring)
        else (.message.content // [] | map(select(.type == "text") | .text) | join(" "))
        end
      ) as $text
    | select($text | test($pat; "i"))
    | "\($date) \($sid) \($role): \($text[0:180] | gsub("\n";" "))"
  ' "$sf" 2>/dev/null || true
done | sort -u
