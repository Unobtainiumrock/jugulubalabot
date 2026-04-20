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

- **08:45** — Round-two capabilities (wave II of wishlist): pre-Bash
  guard hook (prevents cd/cat/grep/find/echo Bash anti-patterns with
  teaching messages + kill switches), budget-peek `--risk` for
  compaction-proximity (uses cache_read+cache_write+input from latest
  turn; current session currently YELLOW at 143k), `mistake-to-fixture`
  helper closing the Reflect→Evaluate loop, and weekly
  `dead-skill-check.sh` surfacing retire candidates. Guard script
  pipe-tested; settings.json wiring awaiting God approval (file is
  permission-gated even in bypassPermissions mode — safety rail).
  → `memory/project_capabilities_20260420.md`
- **08:35** — Four self-service capabilities shipped in one pass after
  God asked "what capabilities do you wish you had": (1) pre-commit
  eval selector with `FIXTURES=` filter, (2) `state/scratch.md`
  compaction-surviving notepad + SOUL.md ritual, (3) `reports/mistakes.md`
  anti-learning lane with first two backfill entries, (4)
  `scripts/budget-peek.sh` live cost query. Each aligned with an
  explicit goal (SEPL shift-left, coherence, honest self-assessment,
  token governance). Real test: will I actually reach for them in flow.
  → `memory/project_capabilities_20260420.md`, commit TBD
- **08:19** — Reflect dry-run surfaced `Bash+cd` as the 2nd-most-common
  (tool, class) pair (9×), in direct violation of the system-prompt rule.
  Fix: feedback memory + new "Behavioral habits" section in reflect.sh
  that counts `cd`/`echo`/`cat`/`grep`/`find`-via-Bash each day. Makes
  drift measurable before it compounds.
  → `memory/feedback_no_cd_prefix.md`, `scripts/reflect.sh`
- **08:19** — Four reflect.sh extensions shipped: session attribution
  (w/ cost bridge), tool-sequence pairs (adjacent same-session ≥3×),
  cross-day delta (graceful skip if no prior trace), behavioral-habits
  counts. Top finding: `Write:sh → Bash:chmod` 5× — candidate for a
  `script-new` skill once Track 4 ships.
  → `scripts/reflect.sh`
- **07:43** — `.gitignore` negation (`!path`) only works when the parent
  directory is matched via a glob (`reports/*`), not a bare-dir pattern
  (`reports/`). Git won't descend into a fully-ignored dir to evaluate
  negations. Surfaced when first learnings-index commit silently skipped
  the file. → `.gitignore` (959396c)
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
