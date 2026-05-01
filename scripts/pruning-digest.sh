#!/usr/bin/env bash
# Weekly pruning digest — reads state/pruning-candidates.jsonl (sorted coldest-first),
# composes a top-15 Telegram digest, and pushes it to God for human review.
#
# Human-gated by design:
#   - No auto-PR, no auto-delete, no reply parsing.
#   - Empty digest = silent (no Telegram, log-only).
#   - God replies in natural language; Tai acts on the reply manually in a later turn.
#
# Flags:
#   --dry-run   Print composed message to stdout instead of sending. Still logs.
#   --full      Show all rows (no 15-cap). Cron uses the 15-cap path; --full is manual.
#
# Env knobs:
#   PRUNING_DIGEST_TARGET   — chat id (default: 8692339838)
#   PRUNING_DIGEST_CHANNEL  — openclaw channel (default: telegram)
#
# Exit codes:
#   0  digest sent, or empty (silent), or dry-run ok
#   1+ send failure / billing / auth error — cron will surface it

set -uo pipefail

WORKSPACE="/root/.openclaw/workspace"
OPENCLAW="/usr/bin/openclaw"
CANDIDATES="$WORKSPACE/state/pruning-candidates.jsonl"
LOG="$WORKSPACE/state/pruning-digest.log.jsonl"
CHAT_TARGET="${PRUNING_DIGEST_TARGET:-8692339838}"
CHANNEL="${PRUNING_DIGEST_CHANNEL:-telegram}"
TOP_N=15
MAX_MSG_CHARS=3500

DRY_RUN=0
FULL=0
for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=1 ;;
    --full)    FULL=1 ;;
    *) echo "[pruning-digest] unknown arg: $arg" >&2; exit 2 ;;
  esac
done

TS=$(date -u +%Y-%m-%dT%H:%M:%SZ)
TODAY=$(date -u +%F)

log_run() {
  # args: result count total [error] [telegram_message_id]
  local result="$1" count="$2" total="$3" err="${4:-}" mid="${5:-}"
  # jq -cn builds a compact JSON object safely quoting inputs
  jq -cn \
    --arg ts "$TS" \
    --arg result "$result" \
    --argjson count "$count" \
    --argjson total "$total" \
    --arg error "$err" \
    --arg mid "$mid" \
    --argjson dry "$DRY_RUN" \
    --argjson full "$FULL" \
    '{ts:$ts, result:$result, count:$count, total:$total, dry_run:($dry==1), full:($full==1)}
     + (if $error == "" then {} else {error:$error} end)
     + (if $mid   == "" then {} else {telegram_message_id:$mid} end)' \
    >> "$LOG"
}

# --- empty / missing candidates → silent ---
if [ ! -s "$CANDIDATES" ]; then
  log_run "empty" 0 0 "" ""
  exit 0
fi

TOTAL=$(wc -l < "$CANDIDATES" | tr -d ' ')

if [ "$FULL" -eq 1 ]; then
  ROWS_JSON=$(cat "$CANDIDATES")
  SHOWN="$TOTAL"
else
  ROWS_JSON=$(head -n "$TOP_N" "$CANDIDATES")
  SHOWN=$(printf '%s\n' "$ROWS_JSON" | grep -c . || true)
fi

# --- compose message body ---
BODY=$(printf '%s\n' "$ROWS_JSON" | jq -rs '
  def fmt:
    . as $r
    | ($r.path // "?") as $p
    | ($r.heat // 0) as $h
    | ($r.centrality_fan_in // 0) as $fi
    | ($r.git_age_days // 0) as $age
    | ($r.reasons // []) as $reasons
    | "\($p) (heat=\($h | tostring), fan_in=\($fi), \($age)d stale) [keep/drop]"
      + (if ($reasons | length) > 0
           then "\n   reasons: " + ($reasons | join(", "))
           else ""
         end);
  [ .[] | fmt ]
  | to_entries
  | map("\(.key + 1). \(.value)")
  | .[]
')

HEADER="Weekly pruning digest — $TODAY

Heat + centrality + age filter caught $TOTAL candidate$([ "$TOTAL" -eq 1 ] || echo 's'). $(if [ "$FULL" -eq 1 ]; then echo "All rows below (coldest first)."; else echo "Top $TOP_N below (coldest first)."; fi)
Reply with \`keep <path>\` or \`drop <path>\` per row (or freeform). I'll open the PR manually."

FOOTER=""
if [ "$FULL" -ne 1 ] && [ "$TOTAL" -gt "$TOP_N" ]; then
  REMAINING=$((TOTAL - TOP_N))
  FOOTER="
(${REMAINING} more candidates below threshold; re-run \`bash scripts/pruning-candidates.sh && bash scripts/pruning-digest.sh --full\` to see all.)"
fi

MSG="$HEADER

$BODY$FOOTER"

# Telegram caps at 4096; leave headroom for server-side framing.
if [ "${#MSG}" -gt "$MAX_MSG_CHARS" ]; then
  MSG="${MSG:0:$MAX_MSG_CHARS}

[truncated; re-run with --full locally to see all rows]"
fi

# --- dry-run path: stdout only ---
if [ "$DRY_RUN" -eq 1 ]; then
  printf '%s\n' "$MSG"
  log_run "dry-run" "$SHOWN" "$TOTAL" "" ""
  exit 0
fi

# Silenced 2026-05-01: per-lane pushes are off; auto-log-sweep is the funnel.
# Always stash the composed message in reports/ so the heartbeat sweep can
# surface "N pruning candidates this week" without re-running the digest.
SIDECAR="$WORKSPACE/reports/pruning-digest-$TODAY.log"
mkdir -p "$(dirname "$SIDECAR")"
{
  printf '=== pruning-digest %s shown=%s total=%s ===\n' "$TS" "$SHOWN" "$TOTAL"
  printf '%s\n' "$MSG"
} >> "$SIDECAR"

if [ "${OPENCLAW_INSCRIPT_PUSH:-0}" != "1" ]; then
  log_run "silenced" "$SHOWN" "$TOTAL" "" ""
  exit 0
fi

# --- real send via openclaw (same pattern as eval-notify.sh / track2-checkin.sh) ---
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
  # Billing / auth / quota signals: God wants to be told explicitly, not worked around.
  if printf '%s' "$ERR_TEXT" | grep -qiE 'insufficient.*credit|quota|billing|unauthori[sz]ed|401|402|403'; then
    printf '[pruning-digest] Telegram send failed with probable billing/auth error:\n%s\n' "$ERR_TEXT" >&2
  else
    printf '[pruning-digest] Telegram send failed (exit=%s):\n%s\n' "$SEND_EXIT" "$ERR_TEXT" >&2
  fi
  log_run "error" "$SHOWN" "$TOTAL" "$ERR_TEXT" ""
  exit "$SEND_EXIT"
fi

# Try to pull a message id from stdout (best-effort; schema may vary).
MID=$(tr -d '\000' < "$SEND_OUT" | jq -r '.. | .messageId? // .message_id? // empty' 2>/dev/null | head -n1)
log_run "sent" "$SHOWN" "$TOTAL" "" "${MID:-}"
exit 0
