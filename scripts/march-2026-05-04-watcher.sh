#!/usr/bin/env bash
# Watch the march log and push a Telegram digest when done.
# Companion to march-2026-05-04.sh — runs as a separate detached process.
set -uo pipefail

LOG_FILE="/root/.openclaw/workspace/reports/march-2026-05-04.log"
JSONL="/root/.openclaw/workspace/reports/improve-2026-05-04.jsonl"
OPENCLAW="/usr/bin/openclaw"
TARGET="8692339838"

# Wait up to 120 min for the march end marker.
deadline=$(( $(date +%s) + 7200 ))
while [ "$(date +%s)" -lt "$deadline" ]; do
  if [ -f "$LOG_FILE" ] && grep -q "=== march end" "$LOG_FILE"; then
    break
  fi
  sleep 60
done

if ! grep -q "=== march end" "$LOG_FILE" 2>/dev/null; then
  "$OPENCLAW" message send --channel telegram --target "$TARGET" \
    --message "March watcher: 120-min deadline hit, no end marker. Investigate scripts/march-2026-05-04.sh / reports/march-2026-05-04.log." </dev/null
  exit 1
fi

# Build digest from improve-*.jsonl entries from this afternoon.
merged=$(jq -r 'select(.ts | startswith("2026-05-04T1")) | select(.result == "merged") | .slug' "$JSONL" | wc -l)
rolled=$(jq -r 'select(.ts | startswith("2026-05-04T1")) | select(.result == "rollback_regression") | .slug' "$JSONL" | wc -l)
attempted=$((merged + rolled))
master_end=$(git rev-parse --short HEAD)

merged_list=$(jq -r 'select(.ts | startswith("2026-05-04T1")) | select(.result == "merged") | "  ✅ " + .slug' "$JSONL")
rolled_list=$(jq -r 'select(.ts | startswith("2026-05-04T1")) | select(.result == "rollback_regression") | "  🔴 " + .slug + " (" + (.detail | capture("regressions=(?<r>[^ ]+)").r) + ")"' "$JSONL")

msg="March 2026-05-04 done. Master: $master_end. Attempted ${attempted}/8 (#1 merged separately).\nMerged: ${merged}\nRolled back: ${rolled}\n\n${merged_list}\n${rolled_list}\n\nFull log: reports/march-2026-05-04.log"

printf '%b\n' "$msg" | "$OPENCLAW" message send --channel telegram --target "$TARGET" --message "$(cat)"
