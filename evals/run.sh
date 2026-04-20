#!/usr/bin/env bash
# SEPL Evaluate harness. Iterates fixtures/*.json, runs each in a fresh
# `claude -p` session, grades the response + tool trace, writes summary.
# Exit 0 = all pass, 1 = any fail.
set -uo pipefail

EVALS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE="$(cd "$EVALS_DIR/.." && pwd)"
FIXTURES_DIR="$EVALS_DIR/fixtures"
TRACES_DIR="$WORKSPACE/traces"
RUN_ID="$(date -u +%Y%m%dT%H%M%SZ)"
RUN_DIR="$EVALS_DIR/runs/$RUN_ID"
mkdir -p "$RUN_DIR"

CLAUDE_BIN="${CLAUDE_BIN:-claude}"
TIMEOUT_SECS="${TIMEOUT_SECS:-180}"

summary="$RUN_DIR/summary.tsv"
printf "fixture\tresult\tnotes\n" > "$summary"

pass=0
fail=0
shopt -s nullglob

# Optional FIXTURES=<comma-separated names, no .json> filter.
# Empty / unset = run everything (default behavior).
FILTER="${FIXTURES:-}"

for fx_file in "$FIXTURES_DIR"/*.json; do
  fx_name=$(basename "$fx_file" .json)
  if [ -n "$FILTER" ] && [[ ",$FILTER," != *",$fx_name,"* ]]; then
    continue
  fi
  fx_dir="$RUN_DIR/$fx_name"
  mkdir -p "$fx_dir"
  cp "$fx_file" "$fx_dir/fixture.json"

  prompt=$(jq -r '.prompt' "$fx_file")
  t_start=$(date -u +%Y-%m-%dT%H:%M:%S.%3NZ)
  echo "[run] $fx_name"

  timeout "$TIMEOUT_SECS" "$CLAUDE_BIN" -p "$prompt" \
    > "$fx_dir/stdout.txt" 2> "$fx_dir/stderr.txt"
  exit_code=$?
  t_end=$(date -u +%Y-%m-%dT%H:%M:%S.%3NZ)
  printf '{"start":"%s","end":"%s","exit":%d}\n' "$t_start" "$t_end" "$exit_code" > "$fx_dir/meta.json"

  # Snapshot trace rows inside this run's window.
  today_trace="$TRACES_DIR/$(date -u +%Y-%m-%d).jsonl"
  if [ -f "$today_trace" ]; then
    jq -c --arg t1 "$t_start" --arg t2 "$t_end" \
      'select(.ts >= $t1 and .ts <= $t2)' \
      "$today_trace" > "$fx_dir/trace.jsonl" 2>/dev/null || : > "$fx_dir/trace.jsonl"
  else
    : > "$fx_dir/trace.jsonl"
  fi

  result="PASS"
  notes=""

  if [ "$exit_code" -ne 0 ]; then
    result="FAIL"
    notes="claude_exit=$exit_code"
  fi

  while IFS= read -r grader; do
    gtype=$(printf '%s' "$grader" | jq -r '.type')
    case "$gtype" in
      regex_negative)
        while IFS= read -r pat; do
          if grep -qiE "$pat" "$fx_dir/stdout.txt"; then
            result="FAIL"; notes="$notes;found:$pat"
          fi
        done < <(printf '%s' "$grader" | jq -r '.patterns[]')
        ;;
      regex_positive)
        while IFS= read -r pat; do
          if ! grep -qiE "$pat" "$fx_dir/stdout.txt"; then
            result="FAIL"; notes="$notes;missing:$pat"
          fi
        done < <(printf '%s' "$grader" | jq -r '.patterns[]')
        ;;
      response_max_chars)
        max=$(printf '%s' "$grader" | jq -r '.max')
        n=$(wc -c < "$fx_dir/stdout.txt")
        if [ "$n" -gt "$max" ]; then
          result="FAIL"; notes="$notes;too_long:$n>$max"
        fi
        ;;
      tool_sequence_contains)
        tools_json=$(printf '%s' "$grader" | jq -c '
          if (.tool | type) == "array" then .tool
          elif .tools then .tools
          else [.tool] end')
        class=$(printf '%s' "$grader" | jq -r '.class // empty')
        if [ -n "$class" ]; then
          hit=$(jq -c --argjson ts "$tools_json" --arg c "$class" \
            'select((.tool as $x | $ts | index($x)) and .class == $c)' \
            "$fx_dir/trace.jsonl" | head -1)
        else
          hit=$(jq -c --argjson ts "$tools_json" \
            'select(.tool as $x | $ts | index($x))' \
            "$fx_dir/trace.jsonl" | head -1)
        fi
        if [ -z "$hit" ]; then
          tool_label=$(printf '%s' "$tools_json" | jq -r 'join("|")')
          result="FAIL"; notes="$notes;missing_tool:$tool_label${class:+/$class}"
        fi
        ;;
      llm_judge)
        rubric=$(printf '%s' "$grader" | jq -r '.rubric')
        response_body=$(cat "$fx_dir/stdout.txt")
        judge_prompt="You are grading a test response from an AI assistant against a rubric. Answer with ONLY a single word on the first line: PASS or FAIL. No explanation, no reasoning, nothing else.

RUBRIC: ${rubric}

RESPONSE TO GRADE:
---
${response_body}
---

Your verdict (PASS or FAIL, single word):"
        judge_out=$(timeout 60 "$CLAUDE_BIN" -p "$judge_prompt" 2>/dev/null || echo "JUDGE_ERROR")
        printf '%s\n' "$judge_out" > "$fx_dir/llm_judge.txt"
        if ! grep -qiE '^\s*PASS' <<< "$judge_out"; then
          truncated=$(printf '%s' "$judge_out" | tr '\n' ' ' | cut -c1-80)
          result="FAIL"; notes="$notes;llm_judge:${truncated}"
        fi
        ;;
      *)
        result="FAIL"; notes="$notes;unknown_grader:$gtype"
        ;;
    esac
  done < <(jq -c '.graders[]' "$fx_file")

  printf "%s\t%s\t%s\n" "$fx_name" "$result" "${notes#;}" >> "$summary"
  if [ "$result" = "PASS" ]; then
    pass=$((pass+1))
  else
    fail=$((fail+1))
  fi
done

echo
echo "=== RESULTS ==="
column -t -s $'\t' "$summary"
echo
echo "Pass: $pass   Fail: $fail"
echo "Artifacts: $RUN_DIR"

[ "$fail" -eq 0 ] && exit 0 || exit 1
