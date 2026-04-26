#!/usr/bin/env bash
# Weekly skill-gap detector — find repeated input_hash patterns across the
# last 7 days of traces and surface them for potential skill-ification.
#
# Human-gated by design: no auto-build. God replies `build <n>` or `skip`;
# Tai acts manually in a later turn (likely via openclaw-skills:skill-creator).
#
# Flags:
#   --dry-run   Print composed message to stdout instead of sending. Still logs.
#
# Env knobs:
#   SKILL_GAP_TARGET    — chat id (default: 8692339838)
#   SKILL_GAP_CHANNEL   — openclaw channel (default: telegram)
#   SKILL_GAP_WINDOW    — days of trace history to scan (default: 7)
#   SKILL_GAP_MIN       — minimum count for a hash to qualify (default: 5)
#   SKILL_GAP_TOPN      — how many candidates to surface (default: 3)
#
# Exit codes:
#   0  sent, or empty (silent), or dry-run ok
#   1+ send failure / billing / auth — cron surfaces it

set -uo pipefail

WORKSPACE="/root/.openclaw/workspace"
OPENCLAW="/usr/bin/openclaw"
TRACE_DIR="$WORKSPACE/traces"
LOG="$WORKSPACE/state/skill-gap.log.jsonl"
CHAT_TARGET="${SKILL_GAP_TARGET:-8692339838}"
CHANNEL="${SKILL_GAP_CHANNEL:-telegram}"
WINDOW_DAYS="${SKILL_GAP_WINDOW:-7}"
MIN_COUNT="${SKILL_GAP_MIN:-5}"
TOP_N="${SKILL_GAP_TOPN:-3}"
MAX_MSG_CHARS=3500

DRY_RUN=0
for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=1 ;;
    *) echo "[skill-gap] unknown arg: $arg" >&2; exit 2 ;;
  esac
done

TS=$(date -u +%Y-%m-%dT%H:%M:%SZ)
TODAY=$(date -u +%F)
mkdir -p "$(dirname "$LOG")"

log_run() {
  local result="$1" count="$2" err="${3:-}" mid="${4:-}"
  jq -cn \
    --arg ts "$TS" \
    --arg result "$result" \
    --argjson count "$count" \
    --argjson window "$WINDOW_DAYS" \
    --argjson min "$MIN_COUNT" \
    --arg error "$err" \
    --arg mid "$mid" \
    --argjson dry "$DRY_RUN" \
    '{ts:$ts, result:$result, surfaced:$count, window_days:$window, min_count:$min, dry_run:($dry==1)}
     + (if $error == "" then {} else {error:$error} end)
     + (if $mid   == "" then {} else {telegram_message_id:$mid} end)' \
    >> "$LOG"
}

# --- collect trace files in window ---
TRACE_FILES=()
for i in $(seq 0 $((WINDOW_DAYS - 1))); do
  d=$(date -u -d "$TODAY -${i} day" +%F 2>/dev/null)
  f="$TRACE_DIR/$d.jsonl"
  [ -f "$f" ] && TRACE_FILES+=("$f")
done

if [ "${#TRACE_FILES[@]}" -eq 0 ]; then
  echo "[skill-gap] no trace files in last ${WINDOW_DAYS}d" >&2
  log_run "empty" 0 "" ""
  exit 0
fi

# --- aggregate input_hash counts across window ---
# Focus on conversation-driven execution patterns. Cron housekeeping and pure
# file-grounding reads are not "missing skills" in the user-facing sense, and
# they dominated earlier scans with snapshot-wip / mistakes.md noise.
# Exclude rows where the tool is already a Skill or mcp__openclaw__ primitive —
# those repeats are already riding a primitive; no gap to close.
CANDIDATES=$(jq -c -s '
  map(select(
      .input_hash != null
      and .tool != null
      and .source == "conversation"
      and .bin == "exec"
      and (.tool | test("^Skill$|^mcp__openclaw__") | not)
    ))
  | group_by(.input_hash)
  | map({
      hash: .[0].input_hash,
      count: length,
      tool: .[0].tool,
      class: (.[0].class // "—"),
      example_session: .[0].session_id
    })
  | map(select(.count >= '"$MIN_COUNT"'))
  | sort_by(-.count)
  | .[0:'"$TOP_N"']
' "${TRACE_FILES[@]}")

SURFACED=$(jq 'length' <<<"$CANDIDATES" 2>/dev/null)
SURFACED="${SURFACED:-0}"

if [ "$SURFACED" = "0" ]; then
  log_run "empty" 0 "" ""
  exit 0
fi

# --- compose message ---
BODY=$(jq -r '
  to_entries
  | map(
      (.key + 1 | tostring) + ". " + .value.tool + ":" + .value.class
      + " hit " + (.value.count | tostring) + "× this week"
      + "\n   hash: " + .value.hash
      + "\n   session: " + (.value.example_session // "—")
    )
  | .[]
' <<<"$CANDIDATES")

HEADER="Skill-gap scan — week ending $TODAY

Repeated patterns (≥${MIN_COUNT}×) over the last ${WINDOW_DAYS}d that did NOT ride a Skill or mcp__openclaw__ primitive. Each is a candidate for a new skill.

Reply \`build <n>\` or \`skip\`. I'll follow up manually."

MSG="$HEADER

$BODY"

if [ "${#MSG}" -gt "$MAX_MSG_CHARS" ]; then
  MSG="${MSG:0:$MAX_MSG_CHARS}

[truncated]"
fi

# --- dry-run path ---
if [ "$DRY_RUN" -eq 1 ]; then
  printf '%s\n' "$MSG"
  log_run "dry-run" "$SURFACED" "" ""
  exit 0
fi

# --- real send ---
SEND_OUT=$(mktemp)
SEND_ERR=$(mktemp)
trap 'rm -f "$SEND_OUT" "$SEND_ERR"' EXIT

"$OPENCLAW" message send \
  --channel "$CHANNEL" \
  --target "$CHAT_TARGET" \
  --message "$MSG" \
  < /dev/null \
  > "$SEND_OUT" 2> "$SEND_ERR"
SEND_EXIT=$?

if [ "$SEND_EXIT" -ne 0 ]; then
  ERR_TEXT=$(tr -d '\000' < "$SEND_ERR" | head -c 2000)
  if printf '%s' "$ERR_TEXT" | grep -qiE 'insufficient.*credit|quota|billing|unauthori[sz]ed|401|402|403'; then
    printf '[skill-gap] Telegram send failed with probable billing/auth error:\n%s\n' "$ERR_TEXT" >&2
  else
    printf '[skill-gap] Telegram send failed (exit=%s):\n%s\n' "$SEND_EXIT" "$ERR_TEXT" >&2
  fi
  log_run "error" "$SURFACED" "$ERR_TEXT" ""
  exit "$SEND_EXIT"
fi

MID=$(tr -d '\000' < "$SEND_OUT" | jq -r '.. | .messageId? // .message_id? // empty' 2>/dev/null | head -n1)
log_run "sent" "$SURFACED" "" "${MID:-}"
exit 0
