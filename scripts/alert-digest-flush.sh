#!/usr/bin/env bash
# Flush buffered alerts from state/alert-queue.jsonl as a single digest.
# Scheduled for QUIET_END_HOUR (default 07:00 UTC). Collapses everything into
# one message with severity-tagged sections; empties the queue atomically.
#
# Usage:
#   scripts/alert-digest-flush.sh [--dry-run]
set -uo pipefail

WORKSPACE="/root/.openclaw/workspace"
QUEUE="$WORKSPACE/state/alert-queue.jsonl"
OPENCLAW="/usr/bin/openclaw"

DRY=0
for arg in "$@"; do
  [ "$arg" = "--dry-run" ] && DRY=1
done

if [ ! -s "$QUEUE" ]; then
  [ "$DRY" -eq 1 ] && echo "queue empty"
  exit 0
fi

# Atomic drain
DRAIN=$(mktemp)
mv "$QUEUE" "$DRAIN"
: > "$QUEUE"

COUNT=$(wc -l < "$DRAIN" | tr -d ' ')
HEADER="Quiet-hours digest — $(date -u +%Y-%m-%d) 07:00 UTC ($COUNT buffered)"

BODY=$(jq -r '
  . as $e |
  "[\(.severity | ascii_upcase)] \(.source) (\(.ts | sub("T"; " ") | sub("Z";"") | .[0:16]))\n\(.message)\n"
' "$DRAIN")

MSG="$HEADER

$BODY"

if [ "$DRY" -eq 1 ]; then
  printf -- '--- DRY RUN digest ---\n%s\n--- END ---\n' "$MSG"
  # restore — dry-run shouldn't drain
  cat "$DRAIN" >> "$QUEUE"
  rm -f "$DRAIN"
  exit 0
fi

TARGET="${ALERT_TARGET:-8692339838}"
CHANNEL="${ALERT_CHANNEL:-telegram}"
"$OPENCLAW" message send --channel "$CHANNEL" --target "$TARGET" --message "$MSG" < /dev/null
rm -f "$DRAIN"
