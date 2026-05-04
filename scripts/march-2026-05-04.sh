#!/usr/bin/env bash
# One-off march driver for 2026-05-04: drives candidates #3-#8 sequentially
# with quarantine on. Logs each invocation; never aborts on a single rollback.
# Single bash process (no chained subagents to lose track), stdout to LOG_FILE.
set -uo pipefail

WORKSPACE="/root/.openclaw/workspace"
LOG_FILE="$WORKSPACE/reports/march-2026-05-04.log"
SLUGS=(
  sharpen-review-structure-stub-rule-in-soul-md
  sharpen-layer-confusion-rule-in-soul-md
  sharpen-loop-on-infra-friction-rule-in-soul-md
  sharpen-one-shot-cron-recognition-rule-in-soul-md
  sharpen-plain-english-default-rule-in-soul-md
  sharpen-token-burn-proposal-rule-in-soul-md
)

cd "$WORKSPACE"
exec >>"$LOG_FILE" 2>&1
echo "=== march start $(date -u +%FT%TZ) ==="
echo "=== master start: $(git rev-parse --short HEAD) ==="

for slug in "${SLUGS[@]}"; do
  echo
  echo "--- candidate: $slug ($(date -u +%FT%TZ)) ---"
  if ! git diff --quiet || ! git diff --cached --quiet; then
    echo "ABORT: dirty tree before $slug"
    git status -sb
    break
  fi
  branch_now=$(git rev-parse --abbrev-ref HEAD)
  if [ "$branch_now" != "master" ]; then
    echo "ABORT: not on master before $slug (on $branch_now)"
    break
  fi
  IMPROVE_QUARANTINE=token-burn-proposal IMPROVE_TIMEOUT=600 \
    bash scripts/improve.sh select-2026-05-04-stable "$slug"
  rc=$?
  rm -f "$WORKSPACE/--help"
  echo "--- result: $slug rc=$rc ---"
  # If rc=3 (input error) or unexpected, log + continue. Don't abort march.
done

echo
echo "=== march end $(date -u +%FT%TZ) ==="
echo "=== master end: $(git rev-parse --short HEAD) ==="
