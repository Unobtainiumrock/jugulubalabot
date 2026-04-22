#!/usr/bin/env bash
# Unified alert sender with quiet-hours buffering.
# All notification paths should route through here instead of calling
# `openclaw message send` directly. Urgent alerts bypass the buffer; action
# and info alerts land in state/alert-queue.jsonl during quiet hours and get
# flushed as a digest at QUIET_END_HOUR by scripts/alert-digest-flush.sh.
#
# Usage:
#   scripts/send-alert.sh --severity {urgent|action|info} --source <name> \
#                         --message "<text>"
#   scripts/send-alert.sh --severity info --source eval [--message "<text>"]
#       (if --message omitted, reads from stdin)
#
# Env:
#   ALERT_TARGET     telegram chat id (default 8692339838)
#   ALERT_CHANNEL    telegram | ... (default telegram)
#   QUIET_START_HOUR 0-23 UTC (default 0)
#   QUIET_END_HOUR   0-23 UTC (default 7)
#   ALERT_FORCE_SEND 1 = ignore quiet-hours buffering (manual overrides)
set -uo pipefail

WORKSPACE="/root/.openclaw/workspace"
QUEUE="$WORKSPACE/state/alert-queue.jsonl"
OPENCLAW="/usr/bin/openclaw"

SEV=""
SRC=""
MSG=""
while [ $# -gt 0 ]; do
  case "$1" in
    --severity) SEV="$2"; shift 2 ;;
    --source)   SRC="$2"; shift 2 ;;
    --message)  MSG="$2"; shift 2 ;;
    *) shift ;;
  esac
done
[ -z "$SEV" ] && SEV="info"
[ -z "$SRC" ] && SRC="unknown"
case "$SEV" in
  urgent|action|info) ;;
  *) echo "Bad severity: $SEV (urgent|action|info)" >&2; exit 2 ;;
esac
[ -z "$MSG" ] && MSG=$(cat)
if [ -z "$MSG" ]; then
  echo "send-alert: empty message (need --message or stdin)" >&2
  exit 2
fi

TARGET="${ALERT_TARGET:-8692339838}"
CHANNEL="${ALERT_CHANNEL:-telegram}"
QS="${QUIET_START_HOUR:-0}"
QE="${QUIET_END_HOUR:-7}"
FORCE="${ALERT_FORCE_SEND:-0}"
HOUR=$(date -u +%-H)
TAG="[$(printf '%s' "$SEV" | tr '[:lower:]' '[:upper:]')]"

in_quiet_window() {
  if [ "$QS" -le "$QE" ]; then
    [ "$HOUR" -ge "$QS" ] && [ "$HOUR" -lt "$QE" ]
  else
    [ "$HOUR" -ge "$QS" ] || [ "$HOUR" -lt "$QE" ]
  fi
}

send_now() {
  local body="$1"
  "$OPENCLAW" message send --channel "$CHANNEL" --target "$TARGET" --message "$body" < /dev/null
}

mkdir -p "$(dirname "$QUEUE")"

if [ "$FORCE" = "1" ] || [ "$SEV" = "urgent" ] || ! in_quiet_window; then
  send_now "$TAG $MSG"
  exit $?
fi

# Quiet hours for non-urgent: buffer
jq -cn \
  --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --arg sev "$SEV" \
  --arg src "$SRC" \
  --arg msg "$MSG" \
  '{ts: $ts, severity: $sev, source: $src, message: $msg}' \
  >> "$QUEUE"
echo "buffered [$SEV/$SRC] (hour=$HOUR UTC, quiet $QS-$QE)"
