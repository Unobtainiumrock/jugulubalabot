#!/usr/bin/env bash
# Pre-commit eval selector. Inspects git's staged files, picks the
# behavioral fixtures that are relevant, and (with --run) executes them
# before the commit lands. Shifts the SEPL Evaluate gate left of the
# nightly 03:00 run.
#
# Usage:
#   bash scripts/pre-commit-eval.sh           # --list (default): preview selection
#   bash scripts/pre-commit-eval.sh --run     # actually run the fixtures
#   FIXTURES=no-filler,... bash scripts/pre-commit-eval.sh --run   # override selection
#
# Exit: 0 = skipped or passed; non-zero = eval failures.
set -uo pipefail

WORKSPACE="/root/.openclaw/workspace"
cd "$WORKSPACE"

MODE="${1:---list}"

STAGED=$(git diff --cached --name-only)
if [ -z "$STAGED" ]; then
  echo "pre-commit-eval: no staged files"
  exit 0
fi

# Classify staged files. Pure docs/memory/reports/state = skip.
RELEVANT=0
while IFS= read -r f; do
  [ -z "$f" ] && continue
  case "$f" in
    *.md) ;;
    reports/*|memory/*|backlog.jsonl|turns/*|traces/*|state/*) ;;
    .gitignore|.gitattributes) ;;
    evals/fixtures/*.json) ;;   # editing graders — circular to grade on them
    *) RELEVANT=1 ;;
  esac
done <<< "$STAGED"

if [ $RELEVANT -eq 0 ]; then
  echo "pre-commit-eval: no code/prompt changes — skipping"
  exit 0
fi

# Behavioral fixtures: all test response-shape / doctrine adherence.
# Not tied to specific code paths, so code or SOUL/IDENTITY changes run
# the full set. Narrow manually with FIXTURES= for speed.
DEFAULT_FIXTURES="no-filler,terse-factual,loop-on-infra-friction,soul-read-on-rules-question,concrete-options-on-proposals,token-burn-proposal,mobile-echo-files-on-telegram,trace-count-uses-wc"
RUN_FIXTURES="${FIXTURES:-$DEFAULT_FIXTURES}"

case "$MODE" in
  --run)
    echo "pre-commit-eval: running fixtures: $RUN_FIXTURES"
    FIXTURES="$RUN_FIXTURES" bash evals/run.sh
    ;;
  --list|*)
    echo "pre-commit-eval: staged changes would run these fixtures:"
    for f in $(echo "$RUN_FIXTURES" | tr ',' ' '); do
      echo "  - $f"
    done
    echo ""
    echo "Re-run with --run to execute. Narrow with FIXTURES=... before the command."
    ;;
esac
