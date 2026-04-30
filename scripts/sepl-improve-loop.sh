#!/usr/bin/env bash
# sepl-improve-loop.sh — daily SEPL Improve wrapper.
# Wires Reflect→Select→Improve into one cron-driven pass. Picks rank-1 from
# today's select-<date>.md, runs improve.sh with IMPROVE_NO_MERGE=1 (week-1
# safety), and pushes a one-line digest to Telegram.
#
# Schedule: cron 30 3 * * * UTC (after nightly evals + memory dreaming).
#
# Env knobs:
#   IMPROVE_NO_MERGE         — defaults to 1 here (override to 0 to enable auto-merge)
#   SEPL_LOOP_NO_NOTIFY=1    — suppress the Telegram digest (smoke-test mode)
#   SEPL_LOOP_NOTIFY_TARGET  — Telegram chat id (default 8692339838)
#   SEPL_LOOP_NOTIFY_CHANNEL — alert channel (default telegram)
#
# Exit codes:
#   0 = improved-and-left-open OR merged OR green/no-op (success path)
#   1 = improve rolled back (eval gate red or subagent failed)
#   2 = nothing actionable today (no sidecar / no candidates / select failed)
#   3 = improve.sh input error

set -uo pipefail

WORKSPACE="/root/.openclaw/workspace"
TODAY="$(date -u +%F)"
REPORTS="$WORKSPACE/reports"
LOG="$REPORTS/sepl-loop-$TODAY.log"
REVIEW="$REPORTS/reflect-$TODAY-review.md"
SELECT_FILE="$REPORTS/select-$TODAY.md"
DIGEST_TARGET="${SEPL_LOOP_NOTIFY_TARGET:-8692339838}"
DIGEST_CHANNEL="${SEPL_LOOP_NOTIFY_CHANNEL:-telegram}"
OPENCLAW="/usr/bin/openclaw"

notify() {
  if [ "${SEPL_LOOP_NO_NOTIFY:-0}" = "1" ]; then
    echo "[notify-suppressed] $*"
    return 0
  fi
  "$OPENCLAW" message send --channel "$DIGEST_CHANNEL" \
    --target "$DIGEST_TARGET" --message "$1" </dev/null || true
}

main() {
  echo "=== sepl-improve-loop $(date -u +%FT%TZ) ==="
  cd "$WORKSPACE"

  # Step 1 — ensure a review sidecar exists. eval-review-bootstrap.sh seeds
  # one on red eval days; green days fall through here and we lay down a
  # no-op stub so Select always has input.
  if [ ! -f "$REVIEW" ]; then
    echo "step1: no sidecar at $REVIEW — seeding green-day no-op stub"
    cat > "$REVIEW" <<EOF_INNER
# Review — reflect $TODAY

## Hypotheses

1. No-op hypothesis: evals are green and no operator-flagged regressions surfaced today. Logging the no-op so the SEPL loop has an artifact to advance.

## Next-step candidates

- [ ] No change selected; re-run tomorrow.
EOF_INNER
  fi

  # Step 2 — run select.sh. Exit 2 = no unchecked candidates (everything
  # checked off). Exit 3 = invalid review shape.
  bash "$WORKSPACE/scripts/select.sh" "$REVIEW" >&2
  sel_rc=$?
  if [ "$sel_rc" -eq 2 ]; then
    echo "step2: select.sh found no unchecked candidates"
    notify "SEPL loop $TODAY: 🟢 no candidates to improve (all checked off)."
    return 0
  fi
  if [ "$sel_rc" -ne 0 ]; then
    echo "step2: select.sh failed rc=$sel_rc"
    notify "SEPL loop $TODAY: ⚠️ select.sh failed (rc=$sel_rc). Inspect $REVIEW."
    return 2
  fi

  # If the only unchecked candidate is the green-day no-op, skip improve
  # rather than spawn a subagent on a placeholder line.
  unchecked_count=$(grep -c '^- \[ \] ' "$REVIEW" 2>/dev/null || echo 0)
  if [ "$unchecked_count" -eq 1 ] && grep -q '^- \[ \] No change selected' "$REVIEW"; then
    echo "step2: only green-day no-op present; skipping improve"
    notify "SEPL loop $TODAY: 🟢 evals green, no operator hypothesis; skipping improve."
    return 0
  fi

  # Step 3 — pull rank-1 slug from select-<date>.md.
  if [ ! -f "$SELECT_FILE" ]; then
    echo "step3: $SELECT_FILE missing"
    notify "SEPL loop $TODAY: ⚠️ select-$TODAY.md not produced."
    return 2
  fi
  SLUG=$(awk '/^### 1\. `/ { sub(/^### 1\. `/,""); sub(/`.*/,""); print; exit }' "$SELECT_FILE")
  if [ -z "$SLUG" ]; then
    echo "step3: no rank-1 slug found in $SELECT_FILE"
    notify "SEPL loop $TODAY: ⚠️ select-$TODAY.md has no ranked candidates."
    return 2
  fi
  echo "step3: rank-1 slug = $SLUG"

  # Step 4 — improve. Default to IMPROVE_NO_MERGE=1 (week-1 safety). Caller
  # can override by exporting IMPROVE_NO_MERGE=0 before invoking us.
  echo "step4: improve.sh select-$TODAY $SLUG (IMPROVE_NO_MERGE=${IMPROVE_NO_MERGE:-1})"
  IMPROVE_NO_MERGE="${IMPROVE_NO_MERGE:-1}" \
    bash "$WORKSPACE/scripts/improve.sh" "select-$TODAY" "$SLUG"
  imp_rc=$?
  echo "step4: improve.sh exit=$imp_rc"

  case "$imp_rc" in
    0) notify "SEPL loop $TODAY: ✅ merged \`$SLUG\`. branch sepl/$TODAY-$SLUG already in master."
       return 0 ;;
    2) notify "SEPL loop $TODAY: 🟢 evals green; branch \`sepl/$TODAY-$SLUG\` left open for review (week-1 no-merge). diff: git diff master..sepl/$TODAY-$SLUG"
       return 0 ;;
    1) notify "SEPL loop $TODAY: 🔴 rolled back \`$SLUG\`. logs: reports/improve-$TODAY-$SLUG.{subagent,eval}.log"
       return 1 ;;
    3) notify "SEPL loop $TODAY: ⚠️ improve.sh input error for \`$SLUG\` (rc=3)."
       return 3 ;;
    *) notify "SEPL loop $TODAY: ⚠️ improve.sh unexpected exit=$imp_rc for \`$SLUG\`."
       return "$imp_rc" ;;
  esac
}

mkdir -p "$REPORTS"
main 2>&1 | tee -a "$LOG"
exit "${PIPESTATUS[0]}"
