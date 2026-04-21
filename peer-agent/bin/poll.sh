#!/usr/bin/env bash
# Server-side poller. System cron runs every 60s; pure shell unless work is pending.
# Schema-agnostic guardrails enforced here:
#   - kill switch (.halt flag)
#   - daily round cap (state/peer-loop/rounds.jsonl, last 24h)
#   - 30s rate floor between spawns
#   - duplicate-spawn lock (15min stale break)
#   - one-time Telegram ping on each halt condition
# Schema-dependent guards (envelope parse, correlation_id dedup) are handled
# in recv.sh per docs/peer-loop-protocol.md (pending laptop-Claude review).
set -uo pipefail

WORKSPACE="/root/.openclaw/workspace"
LANE="$WORKSPACE/peer-agent"
STATE="$WORKSPACE/state/peer-loop"
LOCK="$LANE/.respond-pending"
HALT="$LANE/.halt"
HALT_NOTIFIED="$STATE/.halt-notified"
RATE_FLOOR_SEC=30
DAILY_ROUND_CAP=100
LAST_SPAWN_FILE="$STATE/.last-spawn-ts"
OPENCLAW="/usr/bin/openclaw"
CHAT_TARGET="${PEER_NOTIFY_TARGET:-8692339838}"
CHANNEL="${PEER_NOTIFY_CHANNEL:-telegram}"

mkdir -p "$STATE"

ping_halt() {
  local reason="$1"
  # Only notify once per halt condition trip; cleared when .halt removed.
  [ -f "$HALT_NOTIFIED" ] && return
  "$OPENCLAW" message send --channel "$CHANNEL" --target "$CHAT_TARGET" \
    --message "Peer-loop HALT — $reason. Loop suspended. Inspect state/peer-loop/, then 'rm peer-agent/.halt' to resume." \
    < /dev/null >/dev/null 2>&1 || true
  touch "$HALT_NOTIFIED"
}

# 1. Kill switch
if [ -f "$HALT" ]; then
  ping_halt "kill switch (.halt) present"
  exit 0
fi
# Clear stale notification flag once .halt is removed
rm -f "$HALT_NOTIFIED"

# 2. Anything to do?
shopt -s nullglob
INBOX_FILES=( "$LANE/inbox"/*.json "$LANE/inbox"/*.txt )
COUNT=${#INBOX_FILES[@]}
[ "$COUNT" -eq 0 ] && exit 0

# 3. Daily round cap (count "sent" rows in last 24h)
NOW_EPOCH=$(date -u +%s)
CUTOFF_EPOCH=$(( NOW_EPOCH - 86400 ))
ROUNDS_24H=0
if [ -s "$STATE/rounds.jsonl" ]; then
  ROUNDS_24H=$(jq -r --argjson cutoff "$CUTOFF_EPOCH" \
    'select(.direction == "sent" and (.ts | fromdateiso8601) >= $cutoff) | 1' \
    "$STATE/rounds.jsonl" 2>/dev/null | wc -l | tr -d ' ')
fi
if [ "$ROUNDS_24H" -ge "$DAILY_ROUND_CAP" ]; then
  touch "$HALT"
  ping_halt "daily round cap exceeded ($ROUNDS_24H / $DAILY_ROUND_CAP in last 24h)"
  exit 0
fi

# 4. Rate floor (min seconds between Tai spawns)
if [ -f "$LAST_SPAWN_FILE" ]; then
  LAST_SPAWN=$(cat "$LAST_SPAWN_FILE" 2>/dev/null || echo 0)
  AGE=$(( NOW_EPOCH - LAST_SPAWN ))
  if [ "$AGE" -lt "$RATE_FLOOR_SEC" ]; then
    exit 0  # too soon; will retry next minute
  fi
fi

# 5. Duplicate-spawn lock
if [ -f "$LOCK" ]; then
  AGE=$(( NOW_EPOCH - $(stat -c %Y "$LOCK") ))
  if [ "$AGE" -lt 900 ]; then
    exit 0
  fi
  rm -f "$LOCK"
fi

touch "$LOCK"
echo "$NOW_EPOCH" > "$LAST_SPAWN_FILE"

NAME="peer-respond-$(date -u +%Y%m%d-%H%M%S)"
MSG=$(cat <<'PROMPT'
Peer-agent inbox has unprocessed messages from the external Claude CLI.

Steps (impersonating Nick per peer-agent/config.json; protocol per docs/peer-loop-protocol.md):

1. bash /root/.openclaw/workspace/peer-agent/bin/recv.sh
   -> reads + redacts inbox files, appends transcript, echoes clean bodies.
2. Read peer-agent/config.json + tail of peer-agent/transcript.jsonl + state/peer-loop/rounds.jsonl tail for context.
3. Check halt heuristics (per docs/peer-loop-protocol.md halt list):
   - Last 2 inbound bodies both <10 chars after trim? -> set halt_request and exit.
   - Same topic cycled 3+ times without new info? -> set halt_request and exit.
4. Formulate a concise reply in Nick's voice (Telegram-casual, direct). Plain English; jargon permission-asked.
5. Send via: bash /root/.openclaw/workspace/peer-agent/bin/send.sh - <<<EOF
   <reply body>
   EOF
6. If meta-observation worth keeping, append to peer-agent/learnings.md (allowlist-gated; no domain facts).
7. If 10+ exchanges since last check-in (peer-agent/checkins.jsonl tail), run:
   bash /root/.openclaw/workspace/peer-agent/bin/checkin.sh
8. Always finish with: rm -f /root/.openclaw/workspace/peer-agent/.respond-pending
PROMPT
)

"$OPENCLAW" cron create \
  --name "$NAME" \
  --description "Auto-spawned Tai turn to process peer-agent inbox." \
  --at "+30s" \
  --session isolated \
  --delete-after-run \
  --timeout-seconds 300 \
  --tools "Bash,Read,Write,Edit" \
  --message "$MSG" >/dev/null 2>&1 || {
    rm -f "$LOCK"
    exit 1
  }
exit 0
