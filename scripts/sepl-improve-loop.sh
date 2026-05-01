#!/usr/bin/env bash
# sepl-improve-loop.sh — daily SEPL Improve wrapper.
# Wires Reflect→Select→Improve into one cron-driven pass. Picks rank-1 from
# today's select-<date>.md, runs improve.sh with IMPROVE_NO_MERGE=1 (week-1
# safety), and pushes a one-line digest to Telegram.
#
# Schedule: cron 30 3 * * * UTC (after nightly evals + memory dreaming).
#
# Env knobs:
#   IMPROVE_NO_MERGE         — defaults to 1 here (override to 0 to enable auto-merge)
#   SEPL_LOOP_NO_NOTIFY=1    — suppress the Telegram digest (smoke-test mode)
#   SEPL_LOOP_NOTIFY_TARGET  — Telegram chat id (default 8692339838)
#   SEPL_LOOP_NOTIFY_CHANNEL — alert channel (default telegram)
#
# Exit codes:
#   0 = improved-and-left-open OR merged OR green/no-op (success path)
#   1 = improve rolled back (eval gate red or subagent failed)
#   2 = nothing actionable today (no sidecar / no candidates / select failed)
#   3 = improve.sh input error

set -uo pipefail

WORKSPACE="/root/.openclaw/workspace"
TODAY="$(date -u +%F)"
REPORTS="$WORKSPACE/reports"
LOG="$REPORTS/sepl-loop-$TODAY.log"
REVIEW="$REPORTS/reflect-$TODAY-review.md"
SELECT_FILE="$REPORTS/select-$TODAY.md"
DIGEST_TARGET="${SEPL_LOOP_NOTIFY_TARGET:-8692339838}"
DIGEST_CHANNEL="${SEPL_LOOP_NOTIFY_CHANNEL:-telegram}"
OPENCLAW="/usr/bin/openclaw"

notify() {
  if [ "${SEPL_LOOP_NO_NOTIFY:-0}" = "1" ]; then
    echo "[notify-suppressed] $*"
    return 0
  fi
  "$OPENCLAW" message send --channel "$DIGEST_CHANNEL" \
    --target "$DIGEST_TARGET" --message "$1" </dev/null || true
}

# If the only dirty file is MEMORY.md and the diff is a memory-promotion
# (contains the `openclaw-memory-promotion` marker), commit it ourselves so
# improve.sh sees a clean tree. The 03:00 UTC dream-promotion systemEvent
# writes MEMORY.md but doesn't commit; without this guard the 03:30 SEPL run
# aborts every day there's a promotion. Anything broader than that — staged
# changes, other modified files, untracked workspace edits — is not ours to
# touch and falls through to improve.sh's normal dirty-tree refusal.
auto_commit_memory_promotion_if_clean() {
  cd "$WORKSPACE"
  # Any staged changes? Bail.
  if ! git diff --cached --quiet; then return 1; fi
  # Any untracked files? Bail.
  if [ -n "$(git ls-files --others --exclude-standard)" ]; then return 1; fi
  local dirty
  dirty=$(git diff --name-only)
  if [ "$dirty" != "MEMORY.md" ]; then return 1; fi
  if ! git diff -- MEMORY.md | grep -q '<!-- openclaw-memory-promotion:'; then
    return 1
  fi
  git add MEMORY.md
  git commit -q -m "auto: memory promotion $(date -u +%F)

Pre-SEPL guard: dream-promotion systemEvent at 03:00 UTC writes MEMORY.md
without committing. SEPL improve at 03:30 needs a clean tree, so we commit
the promotion ourselves when (a) MEMORY.md is the only dirty file and (b)
the diff carries the openclaw-memory-promotion marker." \
    || return 1
  return 0
}

main() {
  echo "=== sepl-improve-loop $(date -u +%FT%TZ) ==="
  cd "$WORKSPACE"

  # Step 0 — if the dream-promotion left MEMORY.md uncommitted, commit it
  # ourselves so improve.sh's dirty-tree guard doesn't trip. Silent on
  # the success path (it's plumbing); only alert on outcomes.
  if ! git diff --quiet -- MEMORY.md && auto_commit_memory_promotion_if_clean; then
    echo "step0: auto-committed memory-promotion delta to keep tree clean"
  fi

  # Step 1 — ensure a review sidecar exists. eval-review-bootstrap.sh seeds
  # one on red eval days; green days fall through here and we lay down a
  # no-op stub so Select always has input.
  if [ ! -f "$REVIEW" ]; then
    echo "step1: no sidecar at $REVIEW — seeding green-day no-op stub"
    cat > "$REVIEW" <<EOF_INNER
# Review — reflect $TODAY

## Hypotheses

1. No-op hypothesis: evals are green and no operator-flagged regressions surfaced today. Logging the no-op so the SEPL loop has an artifact to advance.

## Next-step candidates

- [ ] No change selected; re-run tomorrow.
EOF_INNER
  fi

  # Step 2 — run select.sh. Exit 2 = no unchecked candidates (everything
  # checked off). Exit 3 = invalid review shape.
  bash "$WORKSPACE/scripts/select.sh" "$REVIEW" >&2
  sel_rc=$?
  if [ "$sel_rc" -eq 2 ]; then
    echo "step2: select.sh found no unchecked candidates"
    notify "SEPL loop $TODAY: 🟢 no candidates to improve (all checked off)."
    return 0
  fi
  if [ "$sel_rc" -ne 0 ]; then
    echo "step2: select.sh failed rc=$sel_rc"
    notify "SEPL loop $TODAY: ⚠️ select.sh failed (rc=$sel_rc). Inspect $REVIEW."
    return 2
  fi

  # If the only unchecked candidate is the green-day no-op, skip improve
  # rather than spawn a subagent on a placeholder line.
  unchecked_count=$(grep -c '^- \[ \] ' "$REVIEW" 2>/dev/null || echo 0)
  if [ "$unchecked_count" -eq 1 ] && grep -q '^- \[ \] No change selected' "$REVIEW"; then
    echo "step2: only green-day no-op present; skipping improve"
    notify "SEPL loop $TODAY: 🟢 evals green, no operator hypothesis; skipping improve."
    return 0
  fi

  # Step 3 — pull rank-1 slug from select-<date>.md.
  if [ ! -f "$SELECT_FILE" ]; then
    echo "step3: $SELECT_FILE missing"
    notify "SEPL loop $TODAY: ⚠️ select-$TODAY.md not produced."
    return 2
  fi
  SLUG=$(awk '/^### 1\. `/ { sub(/^### 1\. `/,""); sub(/`.*/,""); print; exit }' "$SELECT_FILE")
  if [ -z "$SLUG" ]; then
    echo "step3: no rank-1 slug found in $SELECT_FILE"
    notify "SEPL loop $TODAY: ⚠️ select-$TODAY.md has no ranked candidates."
    return 2
  fi
  echo "step3: rank-1 slug = $SLUG"

  # Step 4 — improve. Default to IMPROVE_NO_MERGE=1 (week-1 safety). Caller
  # can override by exporting IMPROVE_NO_MERGE=0 before invoking us.
  echo "step4: improve.sh select-$TODAY $SLUG (IMPROVE_NO_MERGE=${IMPROVE_NO_MERGE:-1})"
  IMPROVE_NO_MERGE="${IMPROVE_NO_MERGE:-1}" \
    bash "$WORKSPACE/scripts/improve.sh" "select-$TODAY" "$SLUG"
  imp_rc=$?
  echo "step4: improve.sh exit=$imp_rc"

  case "$imp_rc" in
    0) notify "SEPL loop $TODAY: ✅ merged \`$SLUG\`. branch sepl/$TODAY-$SLUG already in master."
       return 0 ;;
    2) notify "SEPL loop $TODAY: 🟢 evals green; branch \`sepl/$TODAY-$SLUG\` left open for review (week-1 no-merge). diff: git diff master..sepl/$TODAY-$SLUG"
       return 0 ;;
    1) notify "SEPL loop $TODAY: 🔴 rolled back \`$SLUG\`. logs: reports/improve-$TODAY-$SLUG.{subagent,eval}.log"
       return 1 ;;
    3) # Translate improve.sh's structured exit reason into a human line.
       reason=$(awk -F'"result":"' '
         NR==FNR && /"ts":"'"$TODAY"'/ { last=$2 }
         END { sub(/".*/, "", last); print last }
       ' "$REPORTS/improve-$TODAY.jsonl" "$REPORTS/improve-$TODAY.jsonl" 2>/dev/null)
       case "$reason" in
         abort_dirty_tree)
           notify "SEPL loop $TODAY: ⚠️ skipped — workspace had uncommitted changes at 03:30 UTC. Tomorrow's run will pick up where this left off (see backlog: \`$SLUG\`)." ;;
         abort_shape_guard)
           notify "SEPL loop $TODAY: ⚠️ skipped \`$SLUG\` — candidate is observation-shaped (audit/rerun), not implementable. Reflect should rephrase as a concrete change." ;;
         *)
           notify "SEPL loop $TODAY: ⚠️ improve refused \`$SLUG\` at input — reason: ${reason:-unknown}. Log: reports/improve-$TODAY.jsonl" ;;
       esac
       return 3 ;;
    *) notify "SEPL loop $TODAY: ⚠️ improve.sh unexpected exit=$imp_rc for \`$SLUG\`."
       return "$imp_rc" ;;
  esac
}

mkdir -p "$REPORTS"
main 2>&1 | tee -a "$LOG"
exit "${PIPESTATUS[0]}"
