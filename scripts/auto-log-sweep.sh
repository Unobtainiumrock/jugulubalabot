#!/usr/bin/env bash
# auto-log-sweep.sh — self-read of yesterday's automated outputs.
#
# Doctrine (AGENTS.md, "Self-improvement alerts" + "Self-read of automated logs"):
# the agent should read its own automated logs without the user having to
# paste them back. This script extracts the *human-shaped verdict* for each
# automated lane that ran in the last 24h. Raw logs stay in reports/.
#
# Output contract:
#   - First line is exactly one of:
#       Auto-log-sweep [OK]   — every lane succeeded; nothing to surface
#       Auto-log-sweep [ATTN] — at least one lane needs human attention
#       Auto-log-sweep [HEAL] — at least one lane self-healed; FYI only
#   - Subsequent lines (only when ATTN/HEAL): one bullet per affected lane,
#     human-shaped (no rc=N, no raw stderr).
#
# Lanes inspected today:
#   1. SEPL improve loop      (reports/sepl-loop-<date>.log + improve-<date>.jsonl)
#   2. Nightly health check   (reports/nightly-<date>.log,  if present)
#   3. Bin sanity / autoheal  (reports/bin-sanity-<date>.txt, if present)
#   4. MEMORY.md commit lane  (memory-promote-commit cron output via reports/)
#   5. Eval regressions       (reports/eval-notify-<date>.log, silenced 2026-05-01)
#   6. Weekly pruning digest  (state/pruning-digest.log.jsonl, silenced 2026-05-01)
#
# Add new lanes as new automated outputs land in reports/.

set -uo pipefail
WORKSPACE="/root/.openclaw/workspace"
REPORTS="$WORKSPACE/reports"
TODAY="$(date -u +%F)"
YDAY="$(date -u -d 'yesterday' +%F)"

attn=()   # human-shaped lines requiring user attention
heal=()   # FYI lines: lane self-healed

# ---- Lane 1: SEPL improve loop ----
for d in "$TODAY" "$YDAY"; do
  log="$REPORTS/sepl-loop-$d.log"
  jsonl="$REPORTS/improve-$d.jsonl"
  [ -f "$log" ] || continue
  # Most-recent run block in $log is what we judge on.
  last_run=$(awk '/^=== sepl-improve-loop/{ts=$0; out=""} {out=out"\n"$0} END{print out}' "$log")
  # Did it abort dirty-tree?
  if printf '%s' "$last_run" | grep -q 'working tree is dirty'; then
    if printf '%s' "$last_run" | grep -q 'step0: auto-committed'; then
      heal+=("SEPL $d: auto-committed memory-promotion delta, then proceeded.")
    else
      attn+=("SEPL $d: aborted on dirty tree — auto-commit guard did not fire. Inspect $log.")
    fi
  fi
  # Did improve.sh roll back?
  if [ -f "$jsonl" ] && tail -n1 "$jsonl" | grep -q '"result":"rollback'; then
    slug=$(tail -n1 "$jsonl" | sed -n 's/.*"slug":"\([^"]*\)".*/\1/p')
    attn+=("SEPL $d: candidate '$slug' rolled back on eval gate. Inspect reports/improve-$d-$slug.eval.log.")
  fi
done

# ---- Lane 2: Nightly health check ----
for d in "$TODAY" "$YDAY"; do
  log="$REPORTS/nightly-$d.log"
  [ -f "$log" ] || continue
  # nightly.sh prints final exit status; capture FAIL lines.
  if grep -qE '\[(FAIL|ERROR)\]' "$log" 2>/dev/null; then
    fail=$(grep -E '\[(FAIL|ERROR)\]' "$log" | head -1)
    attn+=("Nightly $d: $fail")
  fi
done

# ---- Lane 3: Bin sanity ----
for d in "$TODAY" "$YDAY"; do
  txt="$REPORTS/bin-sanity-$d.txt"
  [ -f "$txt" ] || continue
  if grep -q '^GAP' "$txt" 2>/dev/null; then
    healed=$(grep -c '^HEAL' "$txt" 2>/dev/null || echo 0)
    if [ "$healed" -gt 0 ]; then
      heal+=("Bin sanity $d: $healed classifier gap(s) auto-healed into state/bin-overrides.jsonl.")
    else
      gaps=$(grep -c '^GAP' "$txt" 2>/dev/null || echo 0)
      attn+=("Bin sanity $d: $gaps unhealed gap(s) — see $txt.")
    fi
  fi
done

# ---- Lane 4: Memory promotion commit ----
# If the dream-promotion ran today (memory/MEMORY.md timestamp is today)
# but no `auto: memory promotion <date>` commit landed, the lane is broken.
if [ -f "$WORKSPACE/MEMORY.md" ]; then
  m_mtime=$(date -u -r "$WORKSPACE/MEMORY.md" +%F 2>/dev/null || echo "")
  if [ "$m_mtime" = "$TODAY" ]; then
    if ! git -C "$WORKSPACE" log --since "$TODAY 00:00 UTC" --grep '^auto: memory promotion' --oneline -- MEMORY.md 2>/dev/null | grep -q .; then
      # MEMORY.md touched today but no promotion commit — could be unfired
      # cron, manual edit, or in-flight before 03:10. Only flag if it's past
      # 03:30 (the SEPL run time).
      now_hm=$(date -u +%H%M)
      if (( 10#$now_hm >= 330 )); then
        if ! git -C "$WORKSPACE" diff --quiet -- MEMORY.md; then
          attn+=("Memory promotion $TODAY: MEMORY.md modified today but never committed — promotion-commit cron may have failed.")
        fi
      fi
    fi
  fi
fi

# ---- Lane 5: Eval regressions (silenced in-script push) ----
# eval-notify.sh stashes its composed message into reports/eval-notify-<date>.log
# along with `=== eval-notify <ts> exit=N ===`. Non-zero exit on the most-recent
# block = an unforwarded regression that the user should know about.
for d in "$TODAY" "$YDAY"; do
  log="$REPORTS/eval-notify-$d.log"
  [ -f "$log" ] || continue
  last_exit=$(grep -E '^=== eval-notify .* exit=' "$log" | tail -1 | sed -E 's/.*exit=([0-9]+).*/\1/')
  [ -z "$last_exit" ] && continue
  if [ "$last_exit" != "0" ]; then
    latest_block=$(awk '/^=== eval-notify /{block=""} {block=block"\n"$0} END{print block}' "$log")
    if [ "$last_exit" = "3" ]; then
      first_line=$(printf '%s' "$latest_block" | grep -E '^Eval lane unavailable' | head -1)
      attn+=("Eval lane $d: ${first_line:-infra-unavailable run (see $log)}")
    else
      score_line=$(printf '%s' "$latest_block" | grep -E '^- [0-9]+ failed' | head -1)
      attn+=("Eval regression $d: ${score_line:-non-zero exit (see $log)}")
    fi
  fi
done

# ---- Lane 6: Weekly pruning digest (silenced in-script push) ----
# pruning-digest.sh appends a JSONL line per run; surface today's run if it
# was silenced with a non-empty candidate list.
plog="$WORKSPACE/state/pruning-digest.log.jsonl"
if [ -f "$plog" ]; then
  for d in "$TODAY" "$YDAY"; do
    line=$(grep -F "\"ts\":\"$d" "$plog" 2>/dev/null | tail -1)
    [ -z "$line" ] && continue
    result=$(printf '%s' "$line" | jq -r '.result // ""')
    count=$(printf '%s' "$line" | jq -r '.count // 0')
    total=$(printf '%s' "$line" | jq -r '.total // 0')
    case "$result" in
      silenced|sent)
        [ "$total" -gt 0 ] && attn+=("Pruning digest $d: $total candidate(s) waiting on keep/drop calls — see reports/pruning-digest-$d.log.")
        ;;
      error)
        attn+=("Pruning digest $d: send/log error — see $plog.")
        ;;
    esac
  done
fi

# ---- Verdict ----
if [ "${#attn[@]}" -gt 0 ]; then
  echo "Auto-log-sweep [ATTN]"
  printf -- '- %s\n' "${attn[@]}"
elif [ "${#heal[@]}" -gt 0 ]; then
  echo "Auto-log-sweep [HEAL]"
  printf -- '- %s\n' "${heal[@]}"
else
  echo "Auto-log-sweep [OK]"
fi
