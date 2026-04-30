#!/usr/bin/env bash
# Track 2 check-in — computes readiness since Evaluate-gate shipped
# (2026-04-19) and pushes a state-aware Telegram message to God.
# The readiness gate is data-conditioned, not time-conditioned.
#
# Flags:
#   --dry-run   Print the composed message to stdout; do NOT push to Telegram.
#               Added after 2026-04-21 06:28 mistake: I ran the script manually
#               for "stats" and it fired a real Telegram to God.

set -uo pipefail

DRY_RUN=0
for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=1 ;;
    *) ;;
  esac
done

WORKSPACE="/root/.openclaw/workspace"
OPENCLAW="/usr/bin/openclaw"
CHAT_TARGET="${TRACK2_NOTIFY_TARGET:-8692339838}"
CHANNEL="${TRACK2_NOTIFY_CHANNEL:-telegram}"
SHIP_DATE="2026-04-19"
TODAY=$(date -u +%F)

# Ensure today's reflect report exists
if [ -f "$WORKSPACE/traces/$TODAY.jsonl" ]; then
  bash "$WORKSPACE/scripts/reflect.sh" "$TODAY" >/dev/null 2>&1 || true
fi

# Aggregate stats since ship date
TOTAL=0
SESSIONS_FILE=$(mktemp)
BIN_NULL=0
BIN_NONNULL=0
for f in "$WORKSPACE"/traces/*.jsonl; do
  [ -f "$f" ] || continue
  FNAME=$(basename "$f" .jsonl)
  if [[ "$FNAME" < "$SHIP_DATE" ]]; then continue; fi
  LINES=$(wc -l < "$f" | tr -d ' ')
  TOTAL=$((TOTAL + LINES))
  jq -r '.session_id' "$f" >> "$SESSIONS_FILE"
  NULL_HERE=$(jq -r 'select(.bin == null) | 1' "$f" | wc -l | tr -d ' ')
  NN_HERE=$(jq -r 'select(.bin != null) | 1' "$f" | wc -l | tr -d ' ')
  BIN_NULL=$((BIN_NULL + NULL_HERE))
  BIN_NONNULL=$((BIN_NONNULL + NN_HERE))
done
SESSIONS=$(sort -u "$SESSIONS_FILE" | wc -l | tr -d ' ')
rm -f "$SESSIONS_FILE"

# Days elapsed (informational only; no longer a readiness gate)
DAYS=$(( ( $(date -u -d "$TODAY" +%s) - $(date -u -d "$SHIP_DATE" +%s) ) / 86400 ))

# Bin taxonomy status
BIN_STATUS="null on 100% of rows — bin taxonomy not yet implemented"
if [ "$BIN_NONNULL" -gt 0 ] && [ "$BIN_NULL" -eq 0 ]; then
  BIN_STATUS="non-null on 100% of rows since ship date — taxonomy LIVE"
elif [ "$BIN_NONNULL" -gt 0 ]; then
  PCT=$(awk -v nn="$BIN_NONNULL" -v t="$TOTAL" 'BEGIN {printf "%.1f%%", 100.0*nn/t}')
  BIN_STATUS="partial — $PCT of rows tagged"
fi

# Last eval run result. Must use the newest run that has `done.marker` AND
# matches the full fixture-set size — partial subagent gate runs (e.g.
# improve.sh re-running the failing subset via FIXTURES=...) leave a
# half-populated summary.tsv whose pass/fail wouldn't represent the daily
# score. Caught 2026-04-30 when track2-checkin reported "0 pass / 8 fail"
# after improve.sh's gate run (8-fixture filter).
EXPECTED_FIXTURES=$(ls "$WORKSPACE/evals/fixtures"/*.json 2>/dev/null | wc -l | tr -d ' ')
LAST_EVAL_RUN=""
for r in $(ls -t "$WORKSPACE/evals/runs/" 2>/dev/null); do
  marker="$WORKSPACE/evals/runs/$r/done.marker"
  [ -f "$marker" ] || continue
  rp=$(jq -r '.pass // 0' "$marker")
  rf=$(jq -r '.fail // 0' "$marker")
  rt=$(( rp + rf ))
  # Only accept full-set runs. EXPECTED_FIXTURES==0 fallback = pre-fixture-state.
  if [ "$EXPECTED_FIXTURES" -eq 0 ] || [ "$rt" -eq "$EXPECTED_FIXTURES" ]; then
    LAST_EVAL_RUN="$r"
    break
  fi
done
EVAL_STATUS="no completed full-set runs yet"
if [ -n "$LAST_EVAL_RUN" ]; then
  MARKER="$WORKSPACE/evals/runs/$LAST_EVAL_RUN/done.marker"
  EVAL_PASS=$(jq -r '.pass' "$MARKER")
  EVAL_FAIL=$(jq -r '.fail' "$MARKER")
  EVAL_STATUS="$EVAL_PASS pass / $EVAL_FAIL fail (run $LAST_EVAL_RUN)"
fi

REPORT="$WORKSPACE/reports/reflect-$TODAY.md"
REPORT_NOTE=""
if [ -f "$REPORT" ]; then
  REPORT_NOTE="Reflect report: $REPORT"
else
  REPORT_NOTE="No trace data for $TODAY — nothing to reflect on."
fi

# Loop status. Track 4 (Improve) is automated as of 2026-04-29. Read today's
# improve.jsonl tail — if the loop ran, report what it produced; otherwise
# fall back to the legacy "manual Select → Improve" nudge so pre-Track-4
# states still render meaningfully.
REFLECT_DAYS=$(ls "$WORKSPACE"/reports/reflect-*.md 2>/dev/null | wc -l | tr -d ' ')
IMPROVE_LOG="$WORKSPACE/reports/improve-$TODAY.jsonl"
if [ -f "$IMPROVE_LOG" ] && [ -s "$IMPROVE_LOG" ]; then
  # Prefer the latest "real" attempt (subagent actually ran). Dry-runs and
  # abort_dirty_tree are bookkeeping noise — they shouldn't shadow today's
  # real Track 4 outcome.
  LAST_IMP=$(jq -c 'select(.result != "dry_run" and .result != "abort_dirty_tree")' \
              "$IMPROVE_LOG" 2>/dev/null | tail -n 1)
  [ -z "$LAST_IMP" ] && LAST_IMP=$(tail -n 1 "$IMPROVE_LOG")
  IMP_RESULT=$(printf '%s' "$LAST_IMP" | jq -r '.result // "unknown"')
  IMP_SLUG=$(printf '%s' "$LAST_IMP" | jq -r '.slug // "?"')
  case "$IMP_RESULT" in
    merged) LOOP_LINE="Track 4 loop ran today: ✅ merged \`$IMP_SLUG\`." ;;
    left_open) LOOP_LINE="Track 4 loop ran today: 🟢 \`$IMP_SLUG\` passed gate; branch left open (week-1 no-merge)." ;;
    rollback_*) LOOP_LINE="Track 4 loop ran today: 🔴 rolled back \`$IMP_SLUG\` ($IMP_RESULT). See reports/improve-$TODAY-${IMP_SLUG}.{subagent,eval}.log." ;;
    abort_*|no_changes|subagent_fail|commit_fail|merge_conflict)
            LOOP_LINE="Track 4 loop ran today: ⚠️ aborted on \`$IMP_SLUG\` ($IMP_RESULT)." ;;
    dry_run) LOOP_LINE="Track 4 loop: dry-run only on \`$IMP_SLUG\` (no real attempt today)." ;;
    *) LOOP_LINE="Track 4 loop ran today: result=$IMP_RESULT slug=\`$IMP_SLUG\`." ;;
  esac
elif [ "$REFLECT_DAYS" -le 0 ]; then
  LOOP_LINE="If the first three are MET, do the first manual Reflect pass. Reply /reflect to start."
else
  LOOP_LINE="Reflect has run ${REFLECT_DAYS}× so far. Track 4 loop hasn't fired today — check cron + reports/sepl-loop-$TODAY.log."
fi

MSG=$(cat <<EOF
Track 2 check-in — $TODAY (+$DAYS days since Evaluate-gate shipped $SHIP_DATE)

• Total traces since ship: $TOTAL
• Distinct sessions: $SESSIONS
• Bin taxonomy: $BIN_STATUS
• Last eval run: $EVAL_STATUS

$REPORT_NOTE

Track 3 trigger conditions:
- ≥100 invocations: $([ "$TOTAL" -ge 100 ] && echo "MET" || echo "not yet")
- Bin taxonomy in place: $([ "$BIN_NONNULL" -gt 0 ] && echo "MET" || echo "not yet")
- reflect.sh produces readable report: MET
- Repeated pain pattern visible: manual review

$LOOP_LINE
EOF
)

if [ "$DRY_RUN" -eq 1 ]; then
  printf -- '--- DRY RUN: message that WOULD be pushed to %s:%s ---\n%s\n--- END DRY RUN ---\n' \
    "$CHANNEL" "$CHAT_TARGET" "$MSG"
  exit 0
fi

# State-change gate: only fire if (a) a Track 3 trigger flipped, or (b) eval
# pass-rate moved >10 percentage points since last check-in. Avoids daily
# "same numbers" pings. Override: TRACK2_FORCE=1.
STATE_FILE="$WORKSPACE/state/track2-last-state.json"
mkdir -p "$WORKSPACE/state"

TRIG_INVOC=$([ "$TOTAL" -ge 100 ] && echo 1 || echo 0)
TRIG_BIN=$([ "$BIN_NONNULL" -gt 0 ] && echo 1 || echo 0)
PASSRATE=""
if [ -n "$LAST_EVAL_RUN" ]; then
  TOTFX=$(( EVAL_PASS + EVAL_FAIL ))
  if [ "$TOTFX" -gt 0 ]; then
    PASSRATE=$(awk -v p="$EVAL_PASS" -v t="$TOTFX" 'BEGIN {printf "%.2f", p/t}')
  fi
fi

STATE_NOW=$(jq -cn \
  --arg ti "$TRIG_INVOC" --arg tb "$TRIG_BIN" \
  --arg pr "$PASSRATE" --arg lr "$LAST_EVAL_RUN" \
  '{trig_invoc:$ti, trig_bin:$tb, passrate:$pr, last_run:$lr}')

SHOULD_FIRE=1
if [ "${TRACK2_FORCE:-0}" != "1" ] && [ -f "$STATE_FILE" ]; then
  PREV=$(cat "$STATE_FILE" 2>/dev/null)
  PREV_TI=$(printf '%s' "$PREV" | jq -r '.trig_invoc // ""')
  PREV_TB=$(printf '%s' "$PREV" | jq -r '.trig_bin // ""')
  PREV_PR=$(printf '%s' "$PREV" | jq -r '.passrate // ""')
  FLIP=0
  [ "$PREV_TI" != "$TRIG_INVOC" ] && FLIP=1
  [ "$PREV_TB" != "$TRIG_BIN" ] && FLIP=1
  if [ -n "$PREV_PR" ] && [ -n "$PASSRATE" ]; then
    DELTA=$(awk -v a="$PASSRATE" -v b="$PREV_PR" 'BEGIN{d=a-b; if(d<0)d=-d; print d}')
    if awk -v d="$DELTA" 'BEGIN{exit !(d>0.1)}'; then FLIP=1; fi
  fi
  if [ "$FLIP" -eq 0 ]; then
    SHOULD_FIRE=0
  fi
fi

printf '%s\n' "$STATE_NOW" > "$STATE_FILE"

if [ "$SHOULD_FIRE" -eq 0 ]; then
  echo "track2-checkin: state unchanged since last run — skipping push"
  exit 0
fi

# Track 2 check-in is info-level (status ping, not actionable). Route through
# send-alert for quiet-hours buffering.
ALERT_TARGET="$CHAT_TARGET" ALERT_CHANNEL="$CHANNEL" \
  bash "$WORKSPACE/scripts/send-alert.sh" \
    --severity info \
    --source "track2-checkin" \
    --message "$MSG"
