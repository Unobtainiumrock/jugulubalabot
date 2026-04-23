#!/usr/bin/env bash
# Heartbeat-side check for the reflect-signoff loop.
# If yesterday's reflect review sidecar (reports/reflect-<date>-review.md) is
# missing, emit a Telegram message with inline buttons that route back to the
# `reflect-signoff` plugin for sign-off actions.
#
# Idempotency: a breadcrumb at state/reflect-signoff-<date>.sent is touched
# after each successful send. If it's newer than the most recent heartbeat
# interval (default 45m), we skip re-sending. A tap that creates the sidecar
# retires the breadcrumb for that date automatically (next tick sees no need).
#
# Env:
#   ALERT_TARGET     telegram chat id (default 8692339838)
#   ALERT_CHANNEL    default telegram
#   RESEND_COOLDOWN_SEC  minimum seconds between re-sends for the same date
#                         when the review is still missing (default 2700 = 45m).
#   DATE_OVERRIDE    YYYY-MM-DD for manual testing; default is (yesterday UTC).
set -uo pipefail

WORKSPACE="/root/.openclaw/workspace"
STATE_DIR="$WORKSPACE/state"
REPORTS="$WORKSPACE/reports"
OPENCLAW="/usr/bin/openclaw"

DATE="${DATE_OVERRIDE:-$(date -u -d 'yesterday' +%F)}"
REVIEW="$REPORTS/reflect-${DATE}-review.md"
REFLECT="$REPORTS/reflect-${DATE}.md"
BREADCRUMB="$STATE_DIR/reflect-signoff-${DATE}.sent"

mkdir -p "$STATE_DIR"

# No main reflect file for the date → nothing to sign off on; exit quietly.
if [ ! -f "$REFLECT" ]; then
  exit 0
fi

# Review sidecar exists → signoff done. Clean up any breadcrumb so a
# regressing delete (sidecar removed) would re-alert on the next cycle.
if [ -f "$REVIEW" ]; then
  rm -f "$BREADCRUMB"
  exit 0
fi

# Cooldown check.
COOLDOWN="${RESEND_COOLDOWN_SEC:-2700}"
if [ -f "$BREADCRUMB" ]; then
  SENT_AT=$(stat -c %Y "$BREADCRUMB" 2>/dev/null || echo 0)
  NOW=$(date -u +%s)
  if [ $((NOW - SENT_AT)) -lt "$COOLDOWN" ]; then
    exit 0
  fi
fi

TARGET="${ALERT_TARGET:-8692339838}"
CHANNEL="${ALERT_CHANNEL:-telegram}"

BODY=$(printf 'Reflect %s needs review — sidecar missing.\n\nTap to act:' "$DATE")
BUTTONS=$(printf '[[{"text":"👀 View hypotheses","callback_data":"reflect:view:%s"},{"text":"✅ Approve as-is","callback_data":"reflect:approve:%s"},{"text":"⏭️ Skip","callback_data":"reflect:skip:%s"}]]' "$DATE" "$DATE" "$DATE")

if [ "${DRY_RUN:-0}" = "1" ]; then
  printf 'DRY_RUN: would send --channel=%s --target=%s\nmessage: %s\nbuttons: %s\n' \
    "$CHANNEL" "$TARGET" "$BODY" "$BUTTONS"
  exit 0
fi

"$OPENCLAW" message send \
  --channel "$CHANNEL" \
  --target "$TARGET" \
  --message "$BODY" \
  --buttons "$BUTTONS" < /dev/null
rc=$?
if [ "$rc" -eq 0 ]; then
  touch "$BREADCRUMB"
fi
exit "$rc"
