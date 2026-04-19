#!/usr/bin/env bash
# Bin taxonomy sanity check. Flags classifier gaps:
#   - any "other" bin (means a tool/pattern the classifier doesn't know)
#   - unusually high null ratio on recent traces (classifier regression)
# Exits 0 if healthy, 1 if something looks off.
#
# Usage:
#   bash scripts/bin-sanity.sh              # today
#   bash scripts/bin-sanity.sh 2026-04-19   # specific date

set -uo pipefail

WORKSPACE="/root/.openclaw/workspace"
DATE="${1:-$(date -u +%F)}"
TRACE="$WORKSPACE/traces/$DATE.jsonl"

if [ ! -f "$TRACE" ]; then
  echo "No trace file for $DATE"
  exit 0
fi

TOTAL=$(wc -l < "$TRACE" | tr -d ' ')
NULL=$(jq -r 'select(.bin == null or .bin == "") | 1' "$TRACE" | wc -l | tr -d ' ')
OTHER=$(jq -r 'select(.bin == "other") | 1' "$TRACE" | wc -l | tr -d ' ')
CLASSIFIED=$((TOTAL - NULL))
RATIO=0
if [ "$TOTAL" -gt 0 ]; then
  RATIO=$(awk -v c="$CLASSIFIED" -v t="$TOTAL" 'BEGIN {printf "%.1f", 100.0*c/t}')
fi

echo "=== Bin sanity: $DATE ==="
echo "Total rows:        $TOTAL"
echo "Classified (non-null): $CLASSIFIED ($RATIO%)"
echo "null bins:         $NULL (expected: legacy pre-classifier rows only)"
echo "'other' bins:      $OTHER (expected: 0; >0 = classifier gap)"
echo

STATUS=0

if [ "$OTHER" -gt 0 ]; then
  echo "⚠️  $OTHER row(s) tagged 'other'. Tool/pattern samples:"
  jq -c 'select(.bin == "other") | {tool, class}' "$TRACE" | sort -u | head -10
  STATUS=1
fi

# Since-classifier rows (written after the classifier landed) must not be null.
# Before 2026-04-19 22:18Z everything was null by design; after, expect classified.
CUTOFF="2026-04-19T22:18:00Z"
POST_CLASSIFIER_NULL=$(jq -r --arg cutoff "$CUTOFF" 'select(.ts > $cutoff and .bin == null) | 1' "$TRACE" | wc -l | tr -d ' ')
if [ "$POST_CLASSIFIER_NULL" -gt 0 ]; then
  echo "⚠️  $POST_CLASSIFIER_NULL row(s) written after classifier cutoff but still null — classifier bug?"
  STATUS=1
fi

if [ "$STATUS" -eq 0 ]; then
  echo "✅ Healthy."
fi
exit "$STATUS"
