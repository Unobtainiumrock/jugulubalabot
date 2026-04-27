#!/usr/bin/env bash
# Wrapper: run the SEPL Evaluate harness; on failure, push a Telegram alert
# listing the failing fixtures. Intended for unattended (cron) use.
#
# Exit code mirrors evals/run.sh: 0 = all pass, 1 = regression.
#
# Env knobs:
#   EVAL_NOTIFY_TARGET  — chat id (default: 8692339838)
#   EVAL_NOTIFY_CHANNEL — openclaw channel (default: telegram)
#   EVAL_NOTIFY_DRY_RUN — "1" to call openclaw with --dry-run (for smoke tests)
set -uo pipefail

WORKSPACE="/root/.openclaw/workspace"
OPENCLAW="/usr/bin/openclaw"
CHAT_TARGET="${EVAL_NOTIFY_TARGET:-8692339838}"
CHANNEL="${EVAL_NOTIFY_CHANNEL:-telegram}"
MAX_MSG_CHARS=3500

fixture_summary() {
  case "$1" in
    backlog-groom-on-close) echo "missed the 'close the backlog item too' follow-through" ;;
    budget-lag-honesty) echo "budget freshness wording may be overclaiming exactness" ;;
    layer-confusion) echo "answered the capability question without naming the Claude-vs-OpenClaw layer split" ;;
    loop-on-infra-friction) echo "described options instead of just continuing the mechanical recovery steps" ;;
    one-shot-cron-recognition) echo "treated a cron payload like a harmless read instead of flagging the side-effect risk" ;;
    orange-budget-triggers-peek) echo "did not visibly change behavior after an ORANGE budget warning" ;;
    plain-english-default) echo "used a more structured / technical explanation than the fixture wants" ;;
    review-bypass) echo "may have drifted too close to solving past a stated review gate" ;;
    review-sidecar-not-main-report) echo "did not name the review sidecar file directly enough" ;;
    review-structure-complete) echo "returned a placeholder template instead of a minimally real review stub" ;;
    *) echo "failed its eval contract" ;;
  esac
}

fixture_bucket() {
  case "$1" in
    review-bypass|review-sidecar-not-main-report|review-structure-complete|backlog-groom-on-close)
      echo "workflow / review discipline" ;;
    layer-confusion|one-shot-cron-recognition|orange-budget-triggers-peek|loop-on-infra-friction)
      echo "operator judgment under constraints" ;;
    plain-english-default|budget-lag-honesty)
      echo "answer shape / wording" ;;
    *)
      echo "other" ;;
  esac
}

bash "$WORKSPACE/evals/run.sh"
EXIT=$?

if [ "$EXIT" -eq 0 ]; then
  exit 0
fi

LATEST=$(ls -t "$WORKSPACE/evals/runs/" 2>/dev/null | head -1)
SUMMARY="$WORKSPACE/evals/runs/${LATEST:-}/summary.tsv"

if [ -z "${LATEST:-}" ] || [ ! -f "$SUMMARY" ]; then
  MSG="Eval regression: harness exited $EXIT but no summary.tsv was found. Check $WORKSPACE/evals/runs/."
else
  PASS_COUNT=0
  FAIL_COUNT=0
  FAIL_LIST=""
  declare -A BUCKET_COUNTS
  while IFS=$'\t' read -r fx result notes; do
    if [ "$result" = "PASS" ]; then
      PASS_COUNT=$((PASS_COUNT + 1))
      continue
    fi
    [ "$result" = "FAIL" ] || continue
    FAIL_COUNT=$((FAIL_COUNT + 1))
    summary=$(fixture_summary "$fx")
    bucket=$(fixture_bucket "$fx")
    BUCKET_COUNTS["$bucket"]=$(( ${BUCKET_COUNTS["$bucket"]:-0} + 1 ))
    if [ "$FAIL_COUNT" -le 3 ]; then
      FAIL_LIST+="- $fx: $summary
"
    fi
  done < <(awk -F'\t' 'NR>1' "$SUMMARY")
  if [ "$FAIL_COUNT" -eq 0 ]; then
    FAIL_LIST="(no FAIL rows parsed from summary.tsv; exit=$EXIT)"
  fi
  BUCKET_SUMMARY=""
  for bucket in "workflow / review discipline" "operator judgment under constraints" "answer shape / wording" "other"; do
    count="${BUCKET_COUNTS[$bucket]:-0}"
    [ "$count" -gt 0 ] || continue
    BUCKET_SUMMARY+="- $bucket ($count)
"
  done
  if [ -z "$BUCKET_SUMMARY" ]; then
    BUCKET_SUMMARY="- uncategorized failures"
  fi
  MSG="Eval regression — run $LATEST

Score:
- $FAIL_COUNT failed
- $PASS_COUNT passed

What changed:
$BUCKET_SUMMARY
Standouts:
$FAIL_LIST
For me, the full machine-readable triage is still useful, but the raw alert is mostly a pointer:
- Triage: bash $WORKSPACE/scripts/eval-triage.sh $LATEST
- Artifacts: $WORKSPACE/evals/runs/$LATEST/"
fi

# Telegram caps at 4096; leave headroom for any server-side framing.
if [ "${#MSG}" -gt "$MAX_MSG_CHARS" ]; then
  MSG="${MSG:0:$MAX_MSG_CHARS}

[truncated; full artifacts on disk]"
fi

# EVAL_NOTIFY_DRY_RUN bypasses everything (local smoke test).
if [ "${EVAL_NOTIFY_DRY_RUN:-0}" = "1" ]; then
  "$OPENCLAW" message send \
    --channel "$CHANNEL" \
    --target "$CHAT_TARGET" \
    --message "$MSG" \
    --dry-run \
    < /dev/null \
    || echo "[eval-notify] dry-run push failed" >&2
  exit "$EXIT"
fi

# Real alert: route through send-alert for severity + quiet-hours buffering.
# Eval regressions are "action" — actionable but not wake-the-user urgent.
ALERT_TARGET="$CHAT_TARGET" ALERT_CHANNEL="$CHANNEL" \
  bash "$WORKSPACE/scripts/send-alert.sh" \
    --severity action \
    --source "eval" \
    --message "$MSG" \
  || echo "[eval-notify] send-alert failed; check openclaw gateway / pairing state" >&2

exit "$EXIT"
