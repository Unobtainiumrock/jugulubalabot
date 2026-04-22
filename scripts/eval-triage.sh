#!/usr/bin/env bash
# Triage a failed eval run: prints per-failed-fixture rubric + agent stdout +
# judge verdict side-by-side. Invoked after an eval-notify alert to classify
# each FAIL as (A) genuine behavior gap vs (B) grader too strict.
#
# Usage: scripts/eval-triage.sh [run-id]
#        run-id defaults to the newest run dir under evals/runs/.
set -uo pipefail

WORKSPACE="/root/.openclaw/workspace"
RUNS_DIR="$WORKSPACE/evals/runs"

RUN_ID="${1:-}"
if [ -z "$RUN_ID" ]; then
  RUN_ID=$(ls -t "$RUNS_DIR" 2>/dev/null | head -1)
fi
RUN_DIR="$RUNS_DIR/$RUN_ID"

if [ ! -d "$RUN_DIR" ]; then
  echo "No such run: $RUN_ID" >&2
  exit 2
fi

SUMMARY="$RUN_DIR/summary.tsv"
if [ ! -f "$SUMMARY" ]; then
  echo "No summary.tsv in $RUN_DIR" >&2
  exit 2
fi

echo "=== eval-triage: $RUN_ID ==="
echo

mapfile -t FAILS < <(awk -F'\t' '$2=="FAIL" {print $1}' "$SUMMARY")
if [ "${#FAILS[@]}" -eq 0 ]; then
  echo "No failures to triage."
  exit 0
fi
echo "Failures: ${#FAILS[@]}"
echo

for fx in "${FAILS[@]}"; do
  fx_dir="$RUN_DIR/$fx"
  echo "---------- $fx ----------"

  NOTES=$(awk -F'\t' -v name="$fx" '$1==name {print $3}' "$SUMMARY")
  echo "Grader notes: $NOTES"
  echo

  # Rubric — prefer llm_judge rubric, fall back to description
  RUBRIC=$(jq -r '.graders[] | select(.type=="llm_judge") | .rubric' "$fx_dir/fixture.json" 2>/dev/null | head -c 1200)
  DESC=$(jq -r '.description // ""' "$fx_dir/fixture.json" 2>/dev/null | head -c 400)
  echo "Description:"
  echo "  $DESC"
  if [ -n "$RUBRIC" ]; then
    echo "Rubric (truncated 1200ch):"
    printf '  %s\n' "$RUBRIC"
  fi
  echo

  # Agent stdout — first 800 chars
  STDOUT_SIZE=$(wc -c < "$fx_dir/stdout.txt" 2>/dev/null || echo 0)
  echo "Agent stdout ($STDOUT_SIZE bytes, first 800ch):"
  head -c 800 "$fx_dir/stdout.txt" 2>/dev/null | sed 's/^/  /'
  echo

  # Judge verdict
  JUDGE=$(cat "$fx_dir/llm_judge.txt" 2>/dev/null | tr '\n' ' ' | head -c 300)
  if [ -n "$JUDGE" ]; then
    echo "Judge: $JUDGE"
  fi

  # Exit code
  EXIT=$(jq -r '.exit // "?"' "$fx_dir/meta.json" 2>/dev/null)
  echo "claude_exit: $EXIT"
  echo

  # Classify
  VERDICT="review"
  if [ "$EXIT" = "124" ]; then
    VERDICT="timeout (harness)"
  elif [ "$STDOUT_SIZE" -lt 50 ]; then
    VERDICT="empty response (harness/agent crash)"
  elif [[ "$NOTES" == *"missing_tool"* ]] && [[ "$NOTES" != *"llm_judge:FAIL"* ]]; then
    VERDICT="tool-sequence only (possibly grader-strict)"
  elif [[ "$NOTES" == *"missing:"* ]] && [[ "$NOTES" != *"llm_judge:FAIL"* ]]; then
    VERDICT="regex only (possibly grader-strict)"
  elif [[ "$NOTES" == *"llm_judge:FAIL"* ]] && [[ "$NOTES" != *"missing:"* ]] && [[ "$NOTES" != *"missing_tool"* ]]; then
    VERDICT="judge-only (likely real behavior gap)"
  elif [[ "$NOTES" == *"missing"*"llm_judge:FAIL"* ]]; then
    VERDICT="judge + regex both fail (likely real behavior gap)"
  fi
  echo "Triage verdict: $VERDICT"
  echo
done

echo "=== done ==="
