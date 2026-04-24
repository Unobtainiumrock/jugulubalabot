#!/usr/bin/env bash
set -euo pipefail

WORKSPACE="/root/.openclaw/workspace"
LOG="$WORKSPACE/state/guard-log.jsonl"
OUT_DIR="$WORKSPACE/reports"
DATE="${1:-$(date -u +%F)}"
OUT="$OUT_DIR/guard-bypass-audit-$DATE.md"
mkdir -p "$OUT_DIR"

if [ ! -f "$LOG" ] || [ ! -s "$LOG" ]; then
  cat > "$OUT" <<MARKDOWN
# Guard Bypass Audit — $DATE

_No guard log entries found at \
\`state/guard-log.jsonl\`._
MARKDOWN
  echo "wrote $OUT"
  exit 0
fi

total=$(wc -l < "$LOG" | tr -d ' ')
blocked=$(jq -r 'select(.blocked == true) | 1' "$LOG" | wc -l | tr -d ' ')
bypass_call=$(jq -r 'select(.decision == "bypass_call") | 1' "$LOG" | wc -l | tr -d ' ')
bypass_session=$(jq -r 'select(.decision == "bypass_session") | 1' "$LOG" | wc -l | tr -d ' ')
legacy_rows=$(jq -r 'select(.decision == null) | 1' "$LOG" | wc -l | tr -d ' ')
measured=$((blocked + bypass_call + bypass_session))

if [ "$measured" -gt 0 ]; then
  bypass_pct=$(awk -v b="$bypass_call" -v s="$bypass_session" -v m="$measured" 'BEGIN {printf "%.1f%%", 100.0*(b+s)/m}')
else
  bypass_pct="n/a"
fi

blocked_top=$(jq -r 'select(.blocked == true) | .reason' "$LOG" | sed 's/ (Override:.*$//' | sort | uniq -c | sort -rn | head -5 \
  | awk '{count=$1; $1=""; sub(/^ /, ""); printf "| %s | %s |\n", count, $0}')
[ -n "$blocked_top" ] || blocked_top='| 0 | _none_ |'

recent_bypass=$(jq -r 'select(.decision == "bypass_call" or .decision == "bypass_session") | [.ts, .decision, .cmd] | @tsv' "$LOG" | tail -10 \
  | awk -F'\t' '{printf "| %s | %s | %s |\n", $1, $2, $3}')
[ -n "$recent_bypass" ] || recent_bypass='| _none_ |  |  |'

assessment="Guard is still mostly a hard deny path. No recorded bypasses exceed blocks."
if [ $((bypass_call + bypass_session)) -gt "$blocked" ] && [ "$measured" -gt 0 ]; then
  assessment="Bypasses exceed blocks in the measurable rows; promote noisy patterns from nudge to harder enforcement or tune false positives."
elif [ $((bypass_call + bypass_session)) -gt 0 ]; then
  assessment="Some bypasses exist, but they do not exceed blocks. Keep measuring before hard-failing more patterns."
fi
if [ "$legacy_rows" -gt 0 ] && [ $((bypass_call + bypass_session)) -eq 0 ]; then
  assessment="$assessment Historical rows before bypass instrumentation ($legacy_rows) cannot prove zero bypass usage."
fi

cat > "$OUT" <<MARKDOWN
# Guard Bypass Audit — $DATE

_Audit of \`state/guard-log.jsonl\` for whether the pre-Bash guard is being bypassed often enough to make it a rubber stamp._

## Summary

- Total rows: $total
- Blocked rows: $blocked
- Per-call bypass rows: $bypass_call
- Session-wide bypass rows: $bypass_session
- Legacy rows without explicit decision field: $legacy_rows
- Measurable bypass rate: $bypass_pct

**Assessment:** $assessment

## Top blocked reasons

| Count | Reason |
|-------|--------|
$blocked_top

## Recent bypass rows

| Timestamp | Decision | Command |
|-----------|----------|---------|
$recent_bypass

## Interpretation

- \`blocked=true\` means the guard denied the command.
- \`decision=bypass_call\` means the command contained \`OPENCLAW_GUARD_OFF=1\`.
- \`decision=bypass_session\` means \`state/.guard-off\` disabled the guard for the session.
- Legacy rows predate bypass instrumentation, so earlier history may undercount bypasses.
MARKDOWN

echo "wrote $OUT"
