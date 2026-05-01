---
name: eval-triage
description: Use right after an eval regression alert (eval-notify, auto-log-sweep lane 5, or quiet-hours digest [ACTION] eval line). Walks SEPL step 1: run `scripts/eval-triage.sh <run>`, classify each FAIL as genuine-gap vs grader-too-strict, write `reports/reflect-<date>-review.md` with one hypothesis per genuine gap, and end with the next `scripts/select.sh` invocation. Replaces ad-hoc "open the run dir, eyeball summary.tsv, draft a review by hand" pattern.
---

# eval-triage

## When to reach for this

An eval regression alert just landed. You need to close SEPL step 1 (Reflect → review sidecar) so step 2 (Select) has a concrete artifact to rank. Triggers:

- Telegram alert from `eval-notify.sh` (or its silenced sidecar at `reports/eval-notify-<date>.log`)
- `auto-log-sweep.sh` lane 5 surfacing a regression
- `[ACTION] eval` line in the quiet-hours digest
- A standing `reflect-<date>-review.md` that is missing or empty after a non-clean eval

**Not for**: green eval days (no regressions to triage), eval harness bugs (file in `mistakes.md` instead), or fixtures that fail because the *fixture* is wrong (use `eval-fixture-author` to repair).

## How to use

1. Identify the run id. Newest if unspecified:
   ```
   bash scripts/eval-triage.sh
   ```
   Or pin a specific run:
   ```
   bash scripts/eval-triage.sh 20260501T030006Z
   ```

2. For each `FAIL` row, decide:
   - **(A) genuine behavior gap** → fixture caught a real regression; needs a hypothesis in the review sidecar.
   - **(B) grader too strict / fixture stale** → routes to `eval-fixture-author` for repair, *not* a hypothesis.

3. Write `reports/reflect-<date>-review.md` (bootstrap with `bash scripts/eval-review-bootstrap.sh <run>` if missing). For each (A):

   ```markdown
   ## Hypotheses

   1. Pattern: <one-line shape of the gap, e.g. "answers capability questions without naming layer split">.
      Evidence: eval run <run-id>, fixture(s) `<slug>`.
      Fix: <one concrete next step — e.g. "tighten SOUL.md answer contract for layer-confusion">.
   ```

   Skip empty `Hypotheses` blocks. If the day was green and no genuine gaps fired, write an explicit no-op hypothesis (the `explicit-noop-hypothesis` fixture enforces this).

4. End the skill invocation by naming the next command — never run it yourself unless God has asked for the full SEPL pass:

   ```
   bash scripts/select.sh reflect-<date>-review.md
   ```

## Output contract

The skill is done when:

- `reports/reflect-<date>-review.md` exists with at least one Hypothesis OR an explicit no-op block.
- Each Hypothesis names a fixture, evidence, and a concrete `Fix:` line.
- The user sees the next-command pointer (no implicit Select).

## Eval

Covered today by `evals/fixtures/explicit-noop-hypothesis.json`, `evals/fixtures/review-sidecar-not-main-report.json`, and `evals/fixtures/review-structure-complete.json`. A regression in this skill's behavior trips at least one of them on the next nightly run.
