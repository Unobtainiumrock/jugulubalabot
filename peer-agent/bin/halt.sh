#!/usr/bin/env bash
# Manual kill switch. Creates the .halt flag so poll.sh stops scheduling
# new Tai turns. The next poll cycle pings Telegram once.
# Usage: peer-agent/bin/halt.sh [reason]
set -euo pipefail
LANE="/root/.openclaw/workspace/peer-agent"
REASON="${1:-manual halt}"
touch "$LANE/.halt"
echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) — $REASON" > "$LANE/.halt"
echo "Halt flag set. Resume with: rm $LANE/.halt"
