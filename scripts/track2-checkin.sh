#!/usr/bin/env bash
# Track 2 check-in — fires 7 days after Evaluate-gate shipped (2026-04-19).
# Runs reflect.sh on today's traces, computes aggregate state since 2026-04-19,
# and pushes a state-aware Telegram message to God. One-shot by design.

set -uo pipefail

WORKSPACE="/root/.openclaw/workspace"
OPENCLAW="/usr/bin/openclaw"
CHAT_TARGET="${TRACK2_NOTIFY_TARGET:-8692339838}"
CHANNEL="${TRACK2_NOTIFY_CHANNEL:-telegram}"
SHIP_DATE="2026-04-19"
TODAY=$(date -u +%F)

# Ensure today's reflect report exists
if [ -f "$WORKSPACE/traces/$TODAY.jsonl" ]; then
  bash "$WORKSPACE/scripts/reflect.sh" "$TODAY" >/dev/null 2>&1 || true
fi

# Aggregate stats since ship date
TOTAL=0
SESSIONS_FILE=$(mktemp)
BIN_NULL=0
BIN_NONNULL=0
for f in "$WORKSPACE"/traces/*.jsonl; do
  [ -f "$f" ] || continue
  FNAME=$(basename "$f" .jsonl)
  if [[ "$FNAME" < "$SHIP_DATE" ]]; then continue; fi
  LINES=$(wc -l < "$f" | tr -d ' ')
  TOTAL=$((TOTAL + LINES))
  jq -r '.session_id' "$f" >> "$SESSIONS_FILE"
  NULL_HERE=$(jq -r 'select(.bin == null) | 1' "$f" | wc -l | tr -d ' ')
  NN_HERE=$(jq -r 'select(.bin != null) | 1' "$f" | wc -l | tr -d ' ')
  BIN_NULL=$((BIN_NULL + NULL_HERE))
  BIN_NONNULL=$((BIN_NONNULL + NN_HERE))
done
SESSIONS=$(sort -u "$SESSIONS_FILE" | wc -l | tr -d ' ')
rm -f "$SESSIONS_FILE"

# Days elapsed
DAYS=$(( ( $(date -u -d "$TODAY" +%s) - $(date -u -d "$SHIP_DATE" +%s) ) / 86400 ))

# Bin taxonomy status
BIN_STATUS="null on 100% of rows — bin taxonomy not yet implemented"
if [ "$BIN_NONNULL" -gt 0 ] && [ "$BIN_NULL" -eq 0 ]; then
  BIN_STATUS="non-null on 100% of rows since ship date — taxonomy LIVE"
elif [ "$BIN_NONNULL" -gt 0 ]; then
  PCT=$(awk -v nn="$BIN_NONNULL" -v t="$TOTAL" 'BEGIN {printf "%.1f%%", 100.0*nn/t}')
  BIN_STATUS="partial — $PCT of rows tagged"
fi

# Last eval run result
LAST_EVAL_RUN=$(ls -t "$WORKSPACE/evals/runs/" 2>/dev/null | head -1)
EVAL_STATUS="no runs yet"
if [ -n "$LAST_EVAL_RUN" ]; then
  SUMMARY="$WORKSPACE/evals/runs/$LAST_EVAL_RUN/summary.tsv"
  if [ -f "$SUMMARY" ]; then
    EVAL_PASS=$(awk '$2=="PASS"' "$SUMMARY" | wc -l | tr -d ' ')
    EVAL_FAIL=$(awk '$2=="FAIL"' "$SUMMARY" | wc -l | tr -d ' ')
    EVAL_STATUS="$EVAL_PASS pass / $EVAL_FAIL fail (run $LAST_EVAL_RUN)"
  fi
fi

REPORT="$WORKSPACE/reports/reflect-$TODAY.md"
REPORT_NOTE=""
if [ -f "$REPORT" ]; then
  REPORT_NOTE="Reflect report: $REPORT"
else
  REPORT_NOTE="No trace data for $TODAY — nothing to reflect on."
fi

# Count how many distinct-day Reflect reports exist in reports/. Used to decide
# whether to advertise "first Reflect pass" (0 reports) vs. "close next loop
# iteration" (>=1 report). Stops the check-in from re-running day-zero framing
# forever (caught manually 2026-04-21).
REFLECT_DAYS=$(ls "$WORKSPACE"/reports/reflect-*.md 2>/dev/null | wc -l | tr -d ' ')
if [ "$REFLECT_DAYS" -le 0 ]; then
  LOOP_LINE="If the first three are MET, do the first manual Reflect pass. Reply /reflect to start."
else
  LOOP_LINE="Reflect has run ${REFLECT_DAYS}× so far. Next move is Select → Improve on a pattern today's report surfaced (see Hypotheses section)."
fi

MSG=$(cat <<EOF
Track 2 check-in — $TODAY (+$DAYS days since Evaluate-gate shipped $SHIP_DATE)

• Total traces since ship: $TOTAL
• Distinct sessions: $SESSIONS
• Bin taxonomy: $BIN_STATUS
• Last eval run: $EVAL_STATUS

$REPORT_NOTE

Track 3 trigger conditions:
- ≥100 invocations: $([ "$TOTAL" -ge 100 ] && echo "MET" || echo "not yet")
- ≥1 week daily use: $([ "$DAYS" -ge 7 ] && echo "MET" || echo "not yet ($DAYS/7 days)")
- Bin taxonomy in place: $([ "$BIN_NONNULL" -gt 0 ] && echo "MET" || echo "not yet")
- reflect.sh produces readable report: MET
- Repeated pain pattern visible: manual review

$LOOP_LINE
EOF
)

"$OPENCLAW" message send --channel "$CHANNEL" --target "$CHAT_TARGET" --message "$MSG" < /dev/null
