#!/usr/bin/env bash
# Push Telegram check-in digest: recent exchanges + learnings tail.
set -uo pipefail
LANE="/root/.openclaw/workspace/peer-agent"
OPENCLAW="/usr/bin/openclaw"
CHAT_TARGET="${PEER_NOTIFY_TARGET:-8692339838}"
CHANNEL="${PEER_NOTIFY_CHANNEL:-telegram}"

TAIL=$(tail -20 "$LANE/transcript.jsonl" 2>/dev/null | \
  jq -r '"[" + .direction + "] " + ((.body // "") | .[0:200])' | head -10)

LEARN=$(awk '/^---$/{found=1; next} found' "$LANE/learnings.md" 2>/dev/null | tail -15)

MSG="Peer-agent check-in

Recent exchanges:
$TAIL

Learnings tail:
$LEARN

Insider feedback? Silence = proceed."

"$OPENCLAW" message send --channel "$CHANNEL" --target "$CHAT_TARGET" --message "$MSG" < /dev/null
