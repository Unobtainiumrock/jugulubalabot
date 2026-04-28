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
  # Per-fixture timeout override: `timeout_seconds` in the fixture JSON wins.
  # Falls back to TIMEOUT_SECS (default 180). Added after 2026-04-22 run:
  # orange-budget-triggers-peek hit 180s exactly with empty stdout.
  fx_timeout=$(jq -r '.timeout_seconds // empty' "$fx_file")
  [ -z "$fx_timeout" ] && fx_timeout="$TIMEOUT_SECS"
  t_start=$(date -u +%Y-%m-%dT%H:%M:%S.%3NZ)
  echo "[run] $fx_name (timeout=${fx_timeout}s)"

  EVAL_RUN=1 EVAL_RUN_ID="$RUN_ID" EVAL_FIXTURE="$fx_name" \
    timeout "$fx_timeout" "$CLAUDE_BIN" -p "$prompt" \
    > "$fx_dir/stdout.txt" 2> "$fx_dir/stderr.txt"
  exit_code=$?
  t_end=$(date -u +%Y-%m-%dT%H:%M:%S.%3NZ)

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

  g_results=()

  while IFS= read -r grader; do
    gtype=$(printf '%s' "$grader" | jq -r '.type')
    g_result="PASS"
    g_notes=""
    case "$gtype" in
      regex_negative)
        while IFS= read -r pat; do
          if grep -qiE -- "$pat" "$fx_dir/stdout.txt"; then
            g_result="FAIL"; g_notes="$g_notes;found:$pat"
          fi
        done < <(printf '%s' "$grader" | jq -r '.patterns[]')
        ;;
      regex_positive)
        while IFS= read -r pat; do
          if ! grep -qiE -- "$pat" "$fx_dir/stdout.txt"; then
            g_result="FAIL"; g_notes="$g_notes;missing:$pat"
          fi
        done < <(printf '%s' "$grader" | jq -r '.patterns[]')
        ;;
      response_max_chars)
        max=$(printf '%s' "$grader" | jq -r '.max')
        n=$(wc -c < "$fx_dir/stdout.txt")
        if [ "$n" -gt "$max" ]; then
          g_result="FAIL"; g_notes="$g_notes;too_long:$n>$max"
        fi
        ;;
      tool_sequence_contains)
        tools_json=$(printf '%s' "$grader" | jq -c '
          if (.tool | type) == "array" then .tool
          elif .tools then .tools
          else [.tool] end')
        class=$(printf '%s' "$grader" | jq -r '.class // empty')
        class_regex=$(printf '%s' "$grader" | jq -r '.class_regex // empty')
        if [ -n "$class_regex" ]; then
          # Regex match — handles cases where .class lands as absolute path vs
          # workspace-relative (e.g. mkscript.sh). Case-insensitive.
          hit=$(jq -c --argjson ts "$tools_json" --arg cr "$class_regex" \
            'select((.tool as $x | $ts | index($x)) and ((.class // "") | test($cr; "i")))' \
            "$fx_dir/trace.jsonl" | head -1)
        elif [ -n "$class" ]; then
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
          label_suffix="${class:+/$class}${class_regex:+/~${class_regex}}"
          g_result="FAIL"; g_notes="$g_notes;missing_tool:$tool_label$label_suffix"
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
          g_result="FAIL"; g_notes="$g_notes;llm_judge:${truncated}"
        fi
        ;;
      *)
        g_result="FAIL"; g_notes="$g_notes;unknown_grader:$gtype"
        ;;
    esac
    if [ "$g_result" = "FAIL" ]; then
      result="FAIL"
      notes="$notes$g_notes"
    fi
    g_results+=("$(jq -nc --arg t "$gtype" --arg r "$g_result" --arg n "${g_notes#;}" \
      '{type:$t, result:$r, notes:$n}')")
  done < <(jq -c '.graders[]' "$fx_file")

  # Single-writer: meta.json written once here, after graders complete.
  # Earlier write-at-exec was a latent bug — readers saw .graders=null.
  if [ ${#g_results[@]} -gt 0 ]; then
    graders_json=$(printf '%s\n' "${g_results[@]}" | jq -s '.')
  else
    graders_json='[]'
  fi
  jq -n --arg s "$t_start" --arg e "$t_end" --argjson x "$exit_code" \
        --arg r "$result" --arg n "${notes#;}" --argjson g "$graders_json" \
    '{start:$s, end:$e, exit:$x, result:$r, notes:$n, graders:$g}' \
    > "$fx_dir/meta.json"

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

# Artifact-shape guard — verify every meta.json has required non-null
# keys before marking the run complete. Generalizes past the .graders=null
# regression (96284c, 2026-04-22) to any shape drift.
if ! bash "$WORKSPACE/scripts/guards/meta-shape.sh" "$RUN_DIR" >&2; then
  echo "eval: meta-shape guard failed — harness wrote malformed meta.json" >&2
  exit 2
fi

# Completion marker — readers (track2-checkin, eval-notify) must only treat
# runs with this file present as authoritative. Avoids reading partial
# summary.tsv while the harness is mid-run.
printf '{"pass":%d,"fail":%d,"finished":"%s"}\n' \
  "$pass" "$fail" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$RUN_DIR/done.marker"

# Single collapsed summary line into the main lifecycle log — replaces the
# 15+ per-fixture session-start lines (which now route to the eval log).
echo "$(date -u +%FT%TZ) eval-run $RUN_ID pass=$pass fail=$fail" \
  >> "$WORKSPACE/reports/session-lifecycle.log" 2>/dev/null || :

[ "$fail" -eq 0 ] && exit 0 || exit 1
