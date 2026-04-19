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
  FAILS=$(awk -F'\t' 'NR>1 && $2=="FAIL" {printf "- %s  (%s)\n", $1, $3}' "$SUMMARY")
  if [ -z "$FAILS" ]; then
    FAILS="(no FAIL rows parsed from summary.tsv; exit=$EXIT)"
  fi
  MSG="Eval regression — run $LATEST:

$FAILS

Artifacts: $WORKSPACE/evals/runs/$LATEST/"
fi

# Telegram caps at 4096; leave headroom for any server-side framing.
if [ "${#MSG}" -gt "$MAX_MSG_CHARS" ]; then
  MSG="${MSG:0:$MAX_MSG_CHARS}

[truncated; full artifacts on disk]"
fi

DRY_FLAG=()
if [ "${EVAL_NOTIFY_DRY_RUN:-0}" = "1" ]; then
  DRY_FLAG=(--dry-run)
fi

"$OPENCLAW" message send \
  --channel "$CHANNEL" \
  --target "$CHAT_TARGET" \
  --message "$MSG" \
  "${DRY_FLAG[@]}" \
  < /dev/null \
  || echo "[eval-notify] push failed; check openclaw gateway / pairing state" >&2

exit "$EXIT"
