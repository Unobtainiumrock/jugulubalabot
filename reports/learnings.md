# Learnings — human-annotated index

Append-only. Newest first. Each entry: date, one-line takeaway, pointer(s)
to the real artifact. This file is the **index, not the content** — the
actual learning lives in memory/commits/docs/evals.

## Routing doctrine (so learnings land in the right bucket)

| Kind of learning | Bucket |
|---|---|
| Changes how Tai acts next turn | `~/.claude/.../memory/feedback_*.md` |
| Current project state + context that decays | `~/.claude/.../memory/project_*.md` |
| Shared principle / architecture | `workspace/SOUL.md`, `workspace/ROADMAP.md`, `workspace/docs/*.md` |
| Testable behavioral rule | `workspace/evals/fixtures/*.json` |
| Code-change lineage + the "why" | commit message body |

## Relationship to the Reflect loop

`reports/reflect-*.md` is the **auto-generated** lane — trace-data summary,
eventually hypotheses (once Track 3/4 fires). `reports/learnings.md` is the
**human-annotated** lane — conversation-level decisions Reflect can't see
from traces. The Track 3 first-pass Reflect consumes both.

---

## 2026-04-20

- **07:26** — Auto-generated branches need retention GC from day 1, not
  deferred. Branch-count drift is a real risk for any commit cron.
  → `scripts/snapshot-gc.sh` (c96925a)
- **07:18** — Hourly WIP safety net: capture uncommitted work to a
  separate `snapshots/YYYY-MM-DD` branch rather than committing to
  master. Keeps the manual-push contract for real commits intact.
  → `scripts/snapshot-wip.sh` (50c4089)
- **07:10** — `git stash create -u` returns empty when only untracked
  files exist. Use a scratch index (`GIT_INDEX_FILE=...`) to capture
  tracked + untracked without touching the real index.
  → `scripts/snapshot-wip.sh` (50c4089)
- **06:25** — "X is probably good, right?" from God is a check-in, not
  a decided plan. Give honest counter with a concrete failure case, not
  agreement. Pushback on leading questions is welcome.
  → `memory/feedback_pushback_welcomed.md`
- **06:15** — Eval-grader calibration: when a regex grader false-negatives,
  broaden the regex rather than switch the regex/llm_judge combinator to
  OR. Keep the deterministic floor — LLM judges can be fooled by soft-
  deferral phrasing.
  → `evals/fixtures/token-burn-proposal.json` (b40326b), `memory/feedback_pushback_welcomed.md`
- **06:04** — Data-conditioned triggers beat pure time-based for
  "remind me to do X when Y happens" — the condition is the signal, the
  schedule is just the poll cadence.
  → `scripts/v2-readiness-check.sh` (62c3284), `docs/v2-betterrank-plan.md`
