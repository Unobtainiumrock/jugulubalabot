#!/usr/bin/env bash
# Nightly health check — Tier 1 monitoring (NOT the Track 4 learning loop).
# Fires via openclaw cron at 03:00 UTC. Silent on success, Telegram alert
# on any failure. No edits, no auto-merges — observation only.
#
# Checks:
#   1. Eval fixtures — evals/run.sh (eval-notify.sh sends its own alert on fail)
#   2. Bin classifier health — bin-sanity.sh on yesterday's full day of traces
#
# Exit 0 = all healthy. Non-zero = something fired an alert.

set -uo pipefail

WORKSPACE="/root/.openclaw/workspace"
OPENCLAW="/usr/bin/openclaw"
CHAT_TARGET="${NIGHTLY_NOTIFY_TARGET:-8692339838}"
CHANNEL="${NIGHTLY_NOTIFY_CHANNEL:-telegram}"

OVERALL=0

# --- 1. Eval regression check ---------------------------------------------
# eval-notify.sh exits 0 only if every fixture passes; it sends its own
# Telegram alert on any fail. We don't double-push here.
bash "$WORKSPACE/scripts/eval-notify.sh"
EVAL_EXIT=$?
if [ "$EVAL_EXIT" -ne 0 ]; then
  OVERALL=1
fi

# --- 2. Token accounting for yesterday (runs silent; just refreshes data) --
YESTERDAY=$(date -u -d "yesterday" +%F)
bash "$WORKSPACE/scripts/token-accounting.sh" "$YESTERDAY" >/dev/null 2>&1 || true

# --- 3. Bin classifier health on yesterday's traces -----------------------
BIN_OUTPUT=$(bash "$WORKSPACE/scripts/bin-sanity.sh" "$YESTERDAY" 2>&1)
BIN_EXIT=$?

if [ "$BIN_EXIT" -ne 0 ]; then
  MSG="Bin classifier gap — $YESTERDAY

$BIN_OUTPUT

Decide: add rule / new bin / escalate to LLM classifier.
Review: workspace/traces/$YESTERDAY.jsonl"
  "$OPENCLAW" message send --channel "$CHANNEL" --target "$CHAT_TARGET" \
    --message "$MSG" < /dev/null || true
  OVERALL=1
fi

exit "$OVERALL"
