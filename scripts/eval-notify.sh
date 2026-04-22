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
  # Per-fail block: fixture name, grader notes, first ~200ch of agent stdout.
  # Added 2026-04-22 for alert-triage-from-message (task #12).
  FAIL_BLOCKS=""
  while IFS=$'\t' read -r fx result notes; do
    [ "$result" = "FAIL" ] || continue
    sout=""
    if [ -f "$WORKSPACE/evals/runs/$LATEST/$fx/stdout.txt" ]; then
      sout=$(head -c 200 "$WORKSPACE/evals/runs/$LATEST/$fx/stdout.txt" | tr '\n' ' ')
      [ -n "$sout" ] || sout="(empty stdout)"
    fi
    FAIL_BLOCKS+="- $fx
  notes: $notes
  stdout: $sout
"
  done < <(awk -F'\t' 'NR>1' "$SUMMARY")
  if [ -z "$FAIL_BLOCKS" ]; then
    FAIL_BLOCKS="(no FAIL rows parsed from summary.tsv; exit=$EXIT)"
  fi
  MSG="Eval regression — run $LATEST:

$FAIL_BLOCKS
Triage: bash $WORKSPACE/scripts/eval-triage.sh $LATEST
Artifacts: $WORKSPACE/evals/runs/$LATEST/"
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
