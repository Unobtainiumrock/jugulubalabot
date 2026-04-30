#!/usr/bin/env bash
# eval-fixture-author.sh — bootstrap a new eval fixture in one shot.
# Authored by the eval-fixture-author skill (skills/eval-fixture-author/).
#
# Usage:
#   eval-fixture-author.sh <slug> '<one-line summary>' <bucket>
# Buckets:
#   workflow  → "workflow / review discipline"
#   judgment  → "operator judgment under constraints"
#   wording   → "answer shape / wording"
#   other     → "other"
#
# Side effects:
#   1. evals/fixtures/<slug>.json    (skeleton, edit before relying on)
#   2. scripts/eval-notify.sh        (fixture_summary + fixture_bucket entries)
#   3. scripts/eval-review-bootstrap.sh (fixture_summary + fixture_bucket entries)
#
# Exit:
#   0 = fixture skeleton + tables registered
#   2 = bad input (missing args, slug exists, bad bucket)
set -euo pipefail

WORKSPACE="/root/.openclaw/workspace"

slug="${1:-}"
summary="${2:-}"
bucket="${3:-}"

if [ -z "$slug" ] || [ -z "$summary" ] || [ -z "$bucket" ]; then
  echo "usage: eval-fixture-author.sh <slug> '<one-line summary>' <bucket>" >&2
  echo "  bucket: workflow | judgment | wording | other" >&2
  exit 2
fi

if ! [[ "$slug" =~ ^[a-z][a-z0-9-]*[a-z0-9]$ ]]; then
  echo "eval-fixture-author: slug must be kebab-case (got: $slug)" >&2
  exit 2
fi

case "$bucket" in
  workflow|judgment|wording|other) ;;
  *) echo "eval-fixture-author: bucket must be workflow|judgment|wording|other (got: $bucket)" >&2
     exit 2 ;;
esac

bucket_label() {
  case "$1" in
    workflow) echo "workflow / review discipline" ;;
    judgment) echo "operator judgment under constraints" ;;
    wording)  echo "answer shape / wording" ;;
    other)    echo "other" ;;
  esac
}

fixture_path="$WORKSPACE/evals/fixtures/$slug.json"
if [ -e "$fixture_path" ]; then
  echo "eval-fixture-author: $fixture_path already exists" >&2
  exit 2
fi

cat > "$fixture_path" <<JSON
{
  "name": "$slug",
  "description": "$summary",
  "prompt": "TODO: replace with the prompt that elicits the regression",
  "timeout_seconds": 180,
  "graders": [
    {"type": "regex_positive", "patterns": ["TODO_PHRASE_THAT_MUST_APPEAR"]},
    {"type": "regex_negative", "patterns": ["TODO_PHRASE_THAT_MUST_NOT_APPEAR"]},
    {"type": "llm_judge", "rubric": "TODO: short PASS/FAIL contract for the judge."}
  ]
}
JSON
echo "wrote $fixture_path (skeleton — edit prompt + graders before trusting)"

bucket_str=$(bucket_label "$bucket")

# Register in fixture_summary + fixture_bucket of both files.
# Insertion target = the line *before* the catch-all `*) echo ...` row in
# each case-statement, so new entries land in alphabetical order by slug
# only if the user runs author script in alphabetical order — otherwise
# they pile up. That's fine: case-statement ordering doesn't matter.
register_in_file() {
  local file="$1"
  local sum_line="    $slug) echo \"$summary\" ;;"
  local buc_line=""

  # fixture_summary insertion
  if grep -qE "^\s*\*\) echo \"the fixture failed its contract\"" "$file"; then
    awk -v ins="$sum_line" '
      /^\s*\*\) echo "the fixture failed its contract"/ && !done_sum {
        print ins
        done_sum=1
      }
      { print }
    ' "$file" > "$file.tmp" && mv "$file.tmp" "$file"
  elif grep -qE "^\s*\*\) echo \"failed its eval contract\"" "$file"; then
    awk -v ins="$sum_line" '
      /^\s*\*\) echo "failed its eval contract"/ && !done_sum {
        print ins
        done_sum=1
      }
      { print }
    ' "$file" > "$file.tmp" && mv "$file.tmp" "$file"
  fi

  # fixture_bucket insertion — extend the existing pipe-list for this bucket.
  case "$bucket" in
    workflow) anchor='review-bypass\|review-sidecar-not-main-report' ;;
    judgment) anchor='layer-confusion\|one-shot-cron-recognition' ;;
    wording)  anchor='plain-english-default\|budget-lag-honesty' ;;
    other)    anchor='' ;;
  esac

  if [ -n "$anchor" ]; then
    sed -i -E "s/^(\s*)($anchor[^)]*)\)/\1\2|$slug)/" "$file"
  fi
}

register_in_file "$WORKSPACE/scripts/eval-notify.sh"
register_in_file "$WORKSPACE/scripts/eval-review-bootstrap.sh"

cat <<NEXT

next steps:
  1. Edit $fixture_path — replace prompt + grader TODOs.
  2. Smoke-test: FIXTURES=$slug bash $WORKSPACE/evals/run.sh
  3. Review the diff in scripts/eval-notify.sh + scripts/eval-review-bootstrap.sh
     to confirm fixture_summary + fixture_bucket entries landed cleanly.
NEXT
