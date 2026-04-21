#!/usr/bin/env bash
# SessionStart hook: hygiene for the /new scenario. Runs once per session
# start (fresh invoke, /resume, /compact boundary). Silent on no-op; logs
# every action to reports/session-lifecycle.log so future stalls/loss have
# an audit trail.
#
# Steps:
#   1. Archive CC transcripts older than RETENTION_DAYS into archive/.
#   2. Compact sessions.json: drop entries whose updatedAt is beyond cutoff.
#   3. Kill claude zombies — gateway-parented, --resume != current sid,
#      alive >120s (anything younger is the current turn's own process).
#   4. Reset budget-alert.state → GREEN so the new session starts clean.
#   5. Append a session-start line to reports/session-lifecycle.log.
#
# Env knobs:
#   SESSION_CLEAN_RETENTION_DAYS  — days to keep (default 7)
#   SESSION_CLEAN_DISABLE         — "1" to no-op (smoke-tests)
#   SESSION_CLEAN_DRY_RUN         — "1" to log intent but not modify state
set -uo pipefail

[ "${SESSION_CLEAN_DISABLE:-0}" = "1" ] && exit 0

WORKSPACE="/root/.openclaw/workspace"
CC_PROJECT_DIR="/root/.claude/projects/-root--openclaw-workspace"
GW_SESSIONS="/root/.openclaw/agents/main/sessions/sessions.json"
LIFECYCLE_LOG="$WORKSPACE/reports/session-lifecycle.log"
STATE_DIR="$WORKSPACE/state"
BUDGET_STATE="$STATE_DIR/budget-alert.state"
RETENTION_DAYS="${SESSION_CLEAN_RETENTION_DAYS:-7}"
DRY="${SESSION_CLEAN_DRY_RUN:-0}"

mkdir -p "$STATE_DIR" "$(dirname "$LIFECYCLE_LOG")"

STDIN=""
if ! [ -t 0 ]; then STDIN=$(cat 2>/dev/null || true); fi
CURRENT_SID=$(echo "$STDIN" | jq -r '.session_id // ""' 2>/dev/null || echo "")

TS=$(date -u +%FT%TZ)
NOW_S=$(date -u +%s)

# 1. Archive aged CC transcripts
ARCHIVED=0
if [ -d "$CC_PROJECT_DIR" ]; then
  ARCHIVE_DIR="$CC_PROJECT_DIR/archive"
  [ "$DRY" = "1" ] || mkdir -p "$ARCHIVE_DIR"
  while IFS= read -r f; do
    [ -z "$f" ] && continue
    if [ "$DRY" = "1" ]; then
      ARCHIVED=$((ARCHIVED+1))
    else
      mv "$f" "$ARCHIVE_DIR/" 2>/dev/null && ARCHIVED=$((ARCHIVED+1))
    fi
  done < <(find "$CC_PROJECT_DIR" -maxdepth 1 -name '*.jsonl' -mtime +"$RETENTION_DAYS" -type f 2>/dev/null)
fi

# 2. Compact sessions.json
COMPACTED=0
if [ -f "$GW_SESSIONS" ]; then
  CUTOFF_MS=$(( (NOW_S - RETENTION_DAYS * 86400) * 1000 ))
  BEFORE=$(jq 'keys | length' "$GW_SESSIONS" 2>/dev/null || echo 0)
  TMP=$(mktemp)
  if jq --argjson cutoff "$CUTOFF_MS" --arg current "$CURRENT_SID" \
       'with_entries(select(
          (.value.sessionId // "") == $current or
          (.value.claudeCliSessionId // "") == $current or
          (.value.updatedAt // 0) >= $cutoff
        ))' "$GW_SESSIONS" > "$TMP" 2>/dev/null; then
    AFTER=$(jq 'keys | length' "$TMP" 2>/dev/null || echo 0)
    if [ "$AFTER" -lt "$BEFORE" ] && [ "$AFTER" -gt 0 ]; then
      if [ "$DRY" = "1" ]; then
        COMPACTED=$((BEFORE - AFTER))
        rm -f "$TMP"
      else
        cp "$GW_SESSIONS" "${GW_SESSIONS}.bak.$(date -u +%s)"
        mv "$TMP" "$GW_SESSIONS"
        COMPACTED=$((BEFORE - AFTER))
      fi
    else
      rm -f "$TMP"
    fi
  else
    rm -f "$TMP"
  fi
fi

# 3. Zombie kill
KILLED=0
ZOMBIE_DETAIL=""
GW_PID=$(pgrep -x openclaw-gateway 2>/dev/null | head -1)
if [ -n "$GW_PID" ]; then
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    pid=$(echo "$line" | awk '{print $1}')
    etimes=$(echo "$line" | awk '{print $2}')
    [ -z "$pid" ] && continue
    cmdline=$(tr '\0' ' ' < "/proc/$pid/cmdline" 2>/dev/null || echo "")
    [ -z "$cmdline" ] && continue
    case "$cmdline" in claude*|*'/claude '*) ;; *) continue ;; esac
    if [ -n "$CURRENT_SID" ] && echo "$cmdline" | grep -q -- "--resume $CURRENT_SID"; then
      continue
    fi
    if [ "${etimes:-0}" -lt 120 ]; then continue; fi
    ZOMBIE_DETAIL="$ZOMBIE_DETAIL pid=$pid/${etimes}s"
    if [ "$DRY" != "1" ]; then
      kill "$pid" 2>/dev/null
    fi
    KILLED=$((KILLED+1))
  done < <(ps -o pid=,etimes= --ppid "$GW_PID" 2>/dev/null)
fi

# 4. Reset budget-alert state
[ "$DRY" = "1" ] || echo "GREEN" > "$BUDGET_STATE"

# 5. Budget snapshot + lifecycle log line
BUDGET=$(bash "$WORKSPACE/scripts/budget-peek.sh" --risk 2>/dev/null | head -1 || echo "budget-peek: n/a")
SHORT_SID="${CURRENT_SID:0:8}"
{
  echo "$TS session-start sid=${SHORT_SID:-unknown} archived=$ARCHIVED compacted=$COMPACTED killed=$KILLED dry=$DRY"
  [ -n "$ZOMBIE_DETAIL" ] && echo "  zombies:$ZOMBIE_DETAIL"
  echo "  budget: $BUDGET"
} >> "$LIFECYCLE_LOG"

exit 0
