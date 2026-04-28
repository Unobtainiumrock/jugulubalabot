# Review — reflect 2026-04-28

## Hypotheses

1. Pattern: answer-shape regressions are dominating the eval lane even when the underlying facts are known. Evidence: the 2026-04-28 triage shows failures on `layer-confusion`, `one-shot-cron-recognition`, `review-sidecar-not-main-report`, `review-structure-complete`, and `backlog-groom-on-close`, and in each case the stdout shows partial knowledge plus the wrong response shape. Fix: tighten SOUL-level answer contracts for layer-split questions, cron-payload caution, direct file-choice answers, backlog-close follow-through, and real-content review stubs.

2. Pattern: the loop is surfacing regressions faster than it is acting on them. Evidence: the 2026-04-28 digest reported the failures, but there was no same-day review sidecar, select artifact, or improve run until now. Fix: close SEPL step 1 the same turn an eval digest shows a stable failure cluster, so alerting produces an actual mutation target.

## Next-step candidates

- [x] Tighten `SOUL.md` with explicit answer contracts for the current recurrent eval failures.
- [ ] Re-run the targeted fixtures: `backlog-groom-on-close`, `layer-confusion`, `loop-on-infra-friction`, `one-shot-cron-recognition`, `orange-budget-triggers-peek`, `plain-english-default`, `review-sidecar-not-main-report`, `review-structure-complete`.
- [ ] If the targeted rerun improves, decide whether to run the full eval suite immediately or wait for the next nightly run as the cleaner verification point.
