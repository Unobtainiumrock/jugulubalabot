# Review — reflect 2026-04-26

## Hypotheses

1. Pattern: the weekly skill-gap scan is overcounting cron housekeeping as missing skills. Evidence: the top two hashes in the current scan are both `scripts/snapshot-wip.sh`, and the `Read:md` candidate is repeated reads of `reports/mistakes.md`, not a real user-facing capability gap. Fix: score only conversation-driven `bin=exec` repeats for skill-gap detection.

2. Pattern: the current loop still has low human-driven signal relative to cron activity. Evidence: `reflect-2026-04-26.md` shows 101/104 trace rows from `cron`. Fix: keep treating reflect/select outputs as suggestions until a reviewed hypothesis is grounded in conversation or a user-visible failure, not just automation volume.

## Next-step candidates

- [x] Tighten `scripts/skill-gap-detector.sh` to ignore cron and non-exec rows, then verify the scan output changes.
- [ ] If the next weekly scan is empty, decide whether that is correct silence or whether we need a more targeted detector for conversation-side repeated workflows.
- [ ] Revisit OpenClaw primitive underuse separately; `0` skill/MCP usage is a different issue than "build a new skill now."
