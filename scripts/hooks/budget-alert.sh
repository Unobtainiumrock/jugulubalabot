#!/usr/bin/env bash
# Stop-hook: check budget-peek --risk, push Telegram on escalation into
# ORANGE or RED. State-throttled so the same status doesn't re-fire.
#
# Ran at end of every assistant turn (Stop event). Must be fast + silent;
# configured with async: true so a slow invocation can't stall the turn.
#
# Env knobs:
#   BUDGET_ALERT_TARGET  — Telegram chat id (default 8692339838)
#   BUDGET_ALERT_CHANNEL — openclaw channel (default telegram)
#   BUDGET_ALERT_DISABLE — "1" to no-op (for smoke-tests)
set -uo pipefail

[ "${BUDGET_ALERT_DISABLE:-0}" = "1" ] && exit 0

WORKSPACE="/root/.openclaw/workspace"
STATE_DIR="$WORKSPACE/state"
STATE_FILE="$STATE_DIR/budget-alert.state"
LOG_FILE="$STATE_DIR/budget-alert.log"
OPENCLAW="/usr/bin/openclaw"
CHAT_TARGET="${BUDGET_ALERT_TARGET:-8692339838}"
CHANNEL="${BUDGET_ALERT_CHANNEL:-telegram}"

mkdir -p "$STATE_DIR"

# budget-peek already refreshes from transcripts. Bail silently on any failure —
# a stop-hook that crashes the turn is worse than a silent no-op.
OUTPUT=$(bash "$WORKSPACE/scripts/budget-peek.sh" --risk 2>/dev/null) || exit 0
[ -z "$OUTPUT" ] && exit 0

STATUS=$(echo "$OUTPUT" | grep -oE '\[(GREEN|YELLOW|ORANGE|RED)\]' | head -1 | tr -d '[]')
[ -z "$STATUS" ] && exit 0

LAST="GREEN"
[ -f "$STATE_FILE" ] && LAST=$(cat "$STATE_FILE" 2>/dev/null || echo GREEN)

rank() {
  case "$1" in
    GREEN)  echo 0 ;;
    YELLOW) echo 1 ;;
    ORANGE) echo 2 ;;
    RED)    echo 3 ;;
    *)      echo 0 ;;
  esac
}

CUR_RANK=$(rank "$STATUS")
LAST_RANK=$(rank "$LAST")

# Push only on escalation INTO ORANGE/RED — not on YELLOW churn, not on repeats,
# not on de-escalations (those are silent wins).
if [ "$CUR_RANK" -ge 2 ] && [ "$CUR_RANK" -gt "$LAST_RANK" ]; then
  MSG="Budget alert — context risk escalated to $STATUS

$OUTPUT

Action: save state to state/scratch.md, then /compact or /new before the next big turn."
  if "$OPENCLAW" message send \
      --channel "$CHANNEL" \
      --target "$CHAT_TARGET" \
      --message "$MSG" \
      < /dev/null 2>>"$LOG_FILE"; then
    echo "$(date -u +%FT%TZ) PUSH $LAST -> $STATUS" >> "$LOG_FILE"
  else
    echo "$(date -u +%FT%TZ) PUSH_FAIL $LAST -> $STATUS" >> "$LOG_FILE"
  fi
fi

echo "$STATUS" > "$STATE_FILE"
