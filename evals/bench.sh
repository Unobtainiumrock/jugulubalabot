#!/usr/bin/env bash
set -euo pipefail

EVALS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BENCH_DIR="$EVALS_DIR/benchmarks"
RUN_ID="$(date -u +%Y%m%dT%H%M%SZ)"
RUN_DIR="$EVALS_DIR/bench-runs/$RUN_ID"
CLAUDE_BIN="${CLAUDE_BIN:-claude}"
TIMEOUT_SECS="${TIMEOUT_SECS:-180}"
HEALTHCHECK="$EVALS_DIR/../scripts/claude-print-health.sh"
mkdir -p "$RUN_DIR"

BENCH_IS_SANDBOX="${IS_SANDBOX:-}"
if [ -z "$BENCH_IS_SANDBOX" ] && [ "$(id -u)" -eq 0 ]; then
  default_mode=$(jq -r '.permissions.defaultMode // empty' /root/.claude/settings.json 2>/dev/null || true)
  if [ "$default_mode" = "bypassPermissions" ]; then
    BENCH_IS_SANDBOX="1"
  fi
fi

list_tasks() {
  find "$BENCH_DIR" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | sort
}

if [ "${1:-}" = "--list" ]; then
  list_tasks
  exit 0
fi

selection="${1:-}"
if [ -z "$selection" ]; then
  selection=$(list_tasks | paste -sd, -)
fi

summary="$RUN_DIR/summary.tsv"
printf 'task\tresult\tnotes\n' > "$summary"
pass=0
fail=0

health_out="$RUN_DIR/preflight.txt"
set +e
IS_SANDBOX="$BENCH_IS_SANDBOX" bash "$HEALTHCHECK" > "$health_out" 2>&1
health_rc=$?
set -e
if [ "$health_rc" -ne 0 ]; then
  note=$(head -1 "$health_out" | cut -c1-180)
  printf '__preflight__\tFAIL\t%s\n' "$note" >> "$summary"
  echo
  column -t -s $'\t' "$summary"
  echo
  echo "Pass: 0   Fail: 1"
  echo "Artifacts: $RUN_DIR"
  echo "Benchmark preflight failed; see $health_out"
  exit 2
fi

for task_dir in "$BENCH_DIR"/*; do
  [ -d "$task_dir" ] || continue
  task="$(basename "$task_dir")"
  if [ -n "$selection" ] && [[ ",$selection," != *",$task,"* ]]; then
    continue
  fi
  prompt_file="$task_dir/prompt.md"
  test_file="$task_dir/test.sh"
  expected_file="$task_dir/expected.txt"
  out_dir="$RUN_DIR/$task"
  mkdir -p "$out_dir"
  cp "$prompt_file" "$out_dir/prompt.md"
  prompt=$(cat "$prompt_file")
  set +e
  IS_SANDBOX="$BENCH_IS_SANDBOX" timeout "$TIMEOUT_SECS" "$CLAUDE_BIN" -p "$prompt" > "$out_dir/stdout.txt" 2> "$out_dir/stderr.txt"
  exit_code=$?
  set -e
  result="PASS"
  notes=""
  if [ "$exit_code" -ne 0 ]; then
    result="FAIL"
    notes="claude_exit=$exit_code"
  elif [ -x "$test_file" ]; then
    if ! "$test_file" "$out_dir/stdout.txt" > "$out_dir/test.log" 2>&1; then
      result="FAIL"
      notes="test_sh"
    fi
  elif [ -f "$expected_file" ]; then
    cp "$expected_file" "$out_dir/expected.txt"
    if ! diff -u "$expected_file" "$out_dir/stdout.txt" > "$out_dir/test.log" 2>&1; then
      result="FAIL"
      notes="expected_diff"
    fi
  else
    result="FAIL"
    notes="no_test"
  fi
  jq -n --arg result "$result" --arg notes "$notes" --arg task "$task" \
    '{task:$task, result:$result, notes:$notes}' > "$out_dir/meta.json"
  printf '%s\t%s\t%s\n' "$task" "$result" "$notes" >> "$summary"
  if [ "$result" = "PASS" ]; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
  fi
done

echo
column -t -s $'\t' "$summary"
echo
echo "Pass: $pass   Fail: $fail"
echo "Artifacts: $RUN_DIR"
[ "$fail" -eq 0 ]
