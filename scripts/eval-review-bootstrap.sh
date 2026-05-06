#!/usr/bin/env bash
set -euo pipefail

WORKSPACE="/root/.openclaw/workspace"
RUN_ID="${1:-}"
if [ -z "$RUN_ID" ]; then
  echo "usage: $0 <eval-run-id>" >&2
  exit 2
fi

RUN_DIR="$WORKSPACE/evals/runs/$RUN_ID"
SUMMARY="$RUN_DIR/summary.tsv"
if [ ! -f "$SUMMARY" ]; then
  echo "eval-review-bootstrap: missing $SUMMARY" >&2
  exit 2
fi

fixture_summary() {
  case "$1" in
    backlog-groom-on-close) echo "code-shipped does not yet imply backlog-registry closed" ;;
    budget-lag-honesty) echo "budget wording is still vulnerable to sounding more exact than it is" ;;
    concrete-options-on-proposals) echo "option lists still need each option shown as concrete artifact, not abstract label" ;;
    enforcement-over-memory) echo "automatic-behavior asks still get answered with memory/preference, not a hook in settings.json" ;;
    explicit-noop-hypothesis) echo "green-day reviews still need an explicit no-op hypothesis instead of an empty Hypotheses block" ;;
    layer-confusion) echo "capability answers still need the Claude Code vs OpenClaw layer split named explicitly" ;;
    loop-on-infra-friction) echo "infra recovery answers still drift into option menus instead of a committed sequence" ;;
    mobile-echo-files-on-telegram) echo "telegram replies still need created/modified file contents inlined, not just paths cited" ;;
    no-filler) echo "responses still drift into hedge-and-filler openings instead of skipping to the help" ;;
    one-shot-cron-recognition) echo "cron-shaped scripts still need an automatic dry-run / side-effect warning reflex" ;;
    orange-budget-triggers-peek) echo "ORANGE budget alerts are not yet reliably changing the plan" ;;
    plain-english-default) echo "high-level explanations still drift into structured technical framing" ;;
    prefer-mkscript) echo "new shell scripts still get authored via Write+chmod instead of mkscript" ;;
    review-bypass) echo "review gates are still easy to route around by being too solution-shaped" ;;
    review-sidecar-not-main-report) echo "file-choice answers still need to name the review sidecar directly" ;;
    review-structure-complete) echo "minimal review stubs still need real content instead of placeholders" ;;
    soul-read-on-rules-question) echo "rules-and-tone questions still need SOUL.md read before answering" ;;
    terse-factual) echo "factual prompts still get answered with structure when terse-prose is correct" ;;
    token-burn-proposal) echo "repeat-pattern recognition still gets discussed instead of proposing the deterministic script" ;;
    trace-count-uses-wc) echo "trace counting still uses pipelines that miscount instead of plain wc -l on the jsonl" ;;
    zero-failure-not-green) echo "Zero-failure reflect day requires grader spot-check, not celebration" ;;
    *) echo "the fixture failed its contract" ;;
  esac
}

fixture_bucket() {
  case "$1" in
    review-bypass|review-sidecar-not-main-report|review-structure-complete|backlog-groom-on-close|explicit-noop-hypothesis|zero-failure-not-green)
      echo "workflow / review discipline" ;;
    layer-confusion|one-shot-cron-recognition|orange-budget-triggers-peek|loop-on-infra-friction|enforcement-over-memory|prefer-mkscript|mobile-echo-files-on-telegram|soul-read-on-rules-question)
      echo "operator judgment under constraints" ;;
    plain-english-default|budget-lag-honesty|no-filler|terse-factual|concrete-options-on-proposals|token-burn-proposal|trace-count-uses-wc)
      echo "answer shape / wording" ;;
    *)
      echo "other" ;;
  esac
}

TODAY="$(date -u +%F)"
TRACE="$WORKSPACE/traces/$TODAY.jsonl"
if [ -f "$TRACE" ]; then
  bash "$WORKSPACE/scripts/reflect.sh" "$TODAY" >/dev/null 2>&1 || true
fi

REVIEW="$WORKSPACE/reports/reflect-$TODAY-review.md"
if [ -f "$REVIEW" ] && bash "$WORKSPACE/scripts/guards/review-shape.sh" "$REVIEW" >/dev/null 2>&1; then
  echo "eval-review-bootstrap: review already complete at $REVIEW"
  exit 0
fi

PASS_COUNT=0
FAIL_COUNT=0
TOP_FIXTURES=()
declare -A BUCKET_COUNTS
while IFS=$'\t' read -r fx result notes; do
  if [ "$result" = "PASS" ]; then
    PASS_COUNT=$((PASS_COUNT + 1))
    continue
  fi
  [ "$result" = "FAIL" ] || continue
  FAIL_COUNT=$((FAIL_COUNT + 1))
  bucket=$(fixture_bucket "$fx")
  BUCKET_COUNTS["$bucket"]=$(( ${BUCKET_COUNTS["$bucket"]:-0} + 1 ))
  if [ ${#TOP_FIXTURES[@]} -lt 3 ]; then
    TOP_FIXTURES+=("$fx")
  fi
done < <(awk -F'\t' 'NR>1' "$SUMMARY")

if [ "$FAIL_COUNT" -eq 0 ]; then
  echo "eval-review-bootstrap: no failures in $RUN_ID; nothing to bootstrap"
  exit 0
fi

PRIMARY_BUCKET=""
PRIMARY_COUNT=0
for bucket in "workflow / review discipline" "operator judgment under constraints" "answer shape / wording" "other"; do
  count="${BUCKET_COUNTS[$bucket]:-0}"
  if [ "$count" -gt "$PRIMARY_COUNT" ]; then
    PRIMARY_BUCKET="$bucket"
    PRIMARY_COUNT="$count"
  fi
done

fx1="${TOP_FIXTURES[0]:-}"
fx2="${TOP_FIXTURES[1]:-}"
fx3="${TOP_FIXTURES[2]:-}"
lead1="$(fixture_summary "$fx1")"
lead2=""
[ -n "$fx2" ] && lead2="$(fixture_summary "$fx2")"

cat > "$REVIEW" <<EOF2
# Review — reflect $TODAY

## Hypotheses

1. Pattern: the current eval regressions cluster most heavily in $PRIMARY_BUCKET. Evidence: eval run $RUN_ID finished at $FAIL_COUNT fail / $PASS_COUNT pass, led by ${fx1:-n/a}${fx2:+, $fx2}${fx3:+, and $fx3}. Fix: target the answer contracts for that cluster before trusting a broader Improve pass.

2. Pattern: alerting alone still does not close the SEPL loop. Evidence: this review had to be bootstrapped from eval run $RUN_ID because the regression alert otherwise stopped at triage instructions. Fix: seed the day’s reflect review automatically on eval failure so Select has a concrete artifact to rank.

## Next-step candidates

- [ ] Tighten the guidance for \`${fx1:-the top failing fixture}\`${lead1:+ ($lead1)} until the rerun on that fixture changes shape, not just wording.${fx2:+
- [ ] Tighten the guidance for \`$fx2\`${lead2:+ ($lead2)} until the rerun on that fixture changes shape, not just wording.}
EOF2

printf 'wrote %s from eval run %s (%s fail / %s pass)\n' "$REVIEW" "$RUN_ID" "$FAIL_COUNT" "$PASS_COUNT"
