# Long-Term Memory


## Promoted From Short-Term Memory (2026-04-25)

<!-- openclaw-memory-promotion:memory:memory/2026-04-21.md:1:32 -->
- # 2026-04-21 — day log 8-hour autonomous overnight pass (09:17 → 17:17 UTC). Plan at `reports/overnight-plan-2026-04-21.md`. Six commits landed on `master`; H7 is this entry + MEMORY curation; H8 writes the consolidated report. ## Pre-run signal (pre-09:17) - **05:05** — silent stall; context 241% over 200k budget, 0 compactions all session. Budget-peek capability existed, reflex didn't. Logged to `reports/mistakes.md`. - **05:10** — wrong claim that `/new` kills the prior session via OS process model. Actual state lives in gateway registry + on-disk transcripts; CC layer re-spawns per turn. CC-vs-OpenClaw layer confusion again. Logged to `mistakes.md`. - **06:28** — ran `scripts/track2-checkin.sh` manually thinking it printed stats; it fired Telegram message 338 to God. Same pattern as `feedback_smoketest_vs_live_cron`; had the rule, didn't apply it. Logged to `mistakes.md`. - **07:23** — automated reflect ran (`reports/reflect-2026-04-21.md`). - **08:32** — reflect Hypotheses + Next-step candidates filled in from real signal during a heartbeat pass. ## Overnight commits (09:17 → 15:17 UTC) - **09:17 H1 `e799416`** — closed `mistakes.md` Fix items. Shipped `track2-checkin.sh --dry-run` flag + `budget-peek-watch` task in `HEARTBEAT.md` (hourly; alerts on ORANGE/RED). Capability is now schedule-enforced, not reflex-dependent. - **10:17 H2 `278ff79`** — added `source` field to `scripts/trace.sh` (cron / conversation / subagent / unknown) from `OPENCLAW_MCP_SESSION_KEY`; `scripts/reflect.sh` now prints a "Trace [score=0.954 recalls=8 avg=0.985 source=memory/2026-04-21.md:1-32]
<!-- openclaw-memory-promotion:memory:memory/2026-04-21.md:47:77 -->
- cases (quoted values, nested `$(...)`) deferred. - **14:17 H6 `6157f64`** — closed backlog `12ae6e`. `scripts/nightly.sh` now propagates eval-notify exit code via `bump_overall` helper (`max(step_exits)` instead of flattening to binary 0/1). Shim-tested across 5 scenarios. `eval-notify.sh` itself was already correct — diagnosis found the real shape was exit-class flattening, not swallowing. ## Deferred / dropped - Reflect Hypothesis #3 (audit pre-bash-guard) dropped from the plan at authoring time — guard already denies `cd`/`cat`/`grep`/`find`/`echo`. Today's reflect shows `cd`=0 (✓), `cat`=16, `grep`=6, `find`=5 — the guard is live but Bash-class extractor was double-counting (closed in H5). - Original H5 slot (backlog `6fa171`, `FIXTURES=` filter) skipped; the filter already works in `evals/run.sh` L27–L33. H5 cron retargeted to higher-priority `628dec`. - Behavioral fix for the `orange-budget-triggers-peek` failure — a SOUL.md rule forcing budget-peek/compact on ORANGE-in-context — owned by a later pass. - Heartbeat source-discrimination in H2 — heartbeats reuse the main session, so the `source` field reads `conversation`. Detection via `/proc/$PPID/cmdline` + prompt-content scan is feasible but deferred. ## MEMORY.md curation No net change. Reviewed all 18 entries; all remain valid. Today's work closed capability-use gaps noted in `project_capabilities_20260420.md` (budget-peek now heartbeat-enforced) but the memory's core guidance ("they only pay off with use") is still load-bearing — the 05:05 [score=0.946 recalls=7 avg=1.000 source=memory/2026-04-21.md:47-77]
<!-- openclaw-memory-promotion:memory:memory/2026-04-21.md:70:91 -->
- `/proc/$PPID/cmdline` + prompt-content scan is feasible but deferred. ## MEMORY.md curation No net change. Reviewed all 18 entries; all remain valid. Today's work closed capability-use gaps noted in `project_capabilities_20260420.md` (budget-peek now heartbeat-enforced) but the memory's core guidance ("they only pay off with use") is still load-bearing — the 05:05 mistake was a concrete instance of exactly that. No new durable memory added; all of today's signal is derivable from git log + code + the hour logs. ## State - `state/scratch.md` age ~9h; 48h threshold not crossed; left intact. Next session should wipe on task switch. - `reports/overnight-h[1-6]-2026-04-21.md` all present and gitignored per `reports/*` convention; `overnight-plan-2026-04-21.md` is tracked. - Six commits on `master`, none pushed. God's wake-review is at 17:17 UTC after H8 writes the consolidated report. [score=0.933 recalls=6 avg=1.000 source=memory/2026-04-21.md:70-91]
<!-- openclaw-memory-promotion:memory:memory/2026-04-21.md:27:51 -->
- `track2-checkin.sh --dry-run` flag + `budget-peek-watch` task in `HEARTBEAT.md` (hourly; alerts on ORANGE/RED). Capability is now schedule-enforced, not reflex-dependent. - **10:17 H2 `278ff79`** — added `source` field to `scripts/trace.sh` (cron / conversation / subagent / unknown) from `OPENCLAW_MCP_SESSION_KEY`; `scripts/reflect.sh` now prints a "Trace source breakdown" section. Live cross-day signal starting tomorrow. - **11:17 H3 `b439a76`** — new eval fixture `orange-budget-triggers-peek` — ORANGE-zone budget alert + oversized-context request. Fixture **FAILS against current behavior**, which is the point: the 05:05 mistake is now captured as a regression test. Behavior fix deferred to a future SOUL.md edit. - **12:17 H4 `61a70cf`** — elevated `mkscript` from buried skill to SOUL-level reflex via new bullet under Meta-rules. Addresses reflect Hypothesis #1 (7× `Write:sh → Bash:chmod` pair today, mkscript fired 0×). - **13:17 H5 `4a5ac89`** — closed backlog `628dec`. `scripts/trace.sh` Bash class extractor now strips leading `NAME=VAL` env-var assignments (including `$(cmd)`) before picking the first token, so `TIMEOUT=30 bash foo.sh` classes as `bash`, not `TIMEOUT=30`. Edge cases (quoted values, nested `$(...)`) deferred. - **14:17 H6 `6157f64`** — closed backlog `12ae6e`. `scripts/nightly.sh` now propagates eval-notify exit code via `bump_overall` helper (`max(step_exits)` instead of flattening to binary 0/1). Shim-tested across 5 scenarios. `eval-notify.sh` itself was already correct — [score=0.882 recalls=6 avg=0.939 source=memory/2026-04-21.md:27-51]

## Promoted From Short-Term Memory (2026-04-29)

<!-- openclaw-memory-promotion:memory:memory/2026-04-23.md:4:7 -->
- `reports/reflect-<date>.md` for a `## Hypotheses` section even though the reflect flow keeps hypotheses in the review sidecar. Fixed the plugin to read or create `reports/reflect-<date>-review.md` instead, [score=0.861 recalls=0 avg=0.620 source=memory/2026-04-23.md:4-6]
<!-- openclaw-memory-promotion:memory:memory/2026-04-23.md:8:8 -->
- rather than leaving the section blank. [score=0.861 recalls=0 avg=0.620 source=memory/2026-04-23.md:8-8]
<!-- openclaw-memory-promotion:memory:memory/2026-04-23.md:10:13 -->
- `scripts/guards/review-shape.sh` now validates reflect review completeness and is enforced by `reflect-signoff`, signoff alerts, and `scripts/select.sh`; eval fixture set grew from 15 to 20; new [score=0.861 recalls=0 avg=0.620 source=memory/2026-04-23.md:10-12]
<!-- openclaw-memory-promotion:memory:memory/2026-04-23.md:14:15 -->
- `evals/benchmarks/`; `scripts/budget-peek.sh --live` now reports context risk plus freshness/lag so budget numbers are usable in flow. [score=0.861 recalls=0 avg=0.620 source=memory/2026-04-23.md:14-15]
<!-- openclaw-memory-promotion:memory:memory/2026-04-23.md:17:20 -->
- environment, not model capability: `claude -p` cannot resolve/reach `api.anthropic.com` from this sandbox and cannot write expected state under `/root/.claude`. Converted that diagnosis into [score=0.861 recalls=0 avg=0.620 source=memory/2026-04-23.md:17-19]
<!-- openclaw-memory-promotion:memory:memory/2026-04-23.md:21:22 -->
- on preflight with a `__preflight__` row, and added a daily heartbeat check so benchmark availability is visible without manually retrying. [score=0.861 recalls=0 avg=0.620 source=memory/2026-04-23.md:21-22]

## Promoted From Short-Term Memory (2026-05-01)

<!-- openclaw-memory-promotion:memory:memory/2026-04-25.md:1:1 -->
- 2026-04-25 [score=0.812 recalls=0 avg=0.620 source=memory/2026-04-25.md:1-1]
<!-- openclaw-memory-promotion:memory:memory/2026-04-21.md:3:5 -->
- 8-hour autonomous overnight pass (09:17 → 17:17 UTC). Plan at `reports/overnight-plan-2026-04-21.md`. Six commits landed on `master`; H7 is this entry + MEMORY curation; H8 writes the consolidated report. [score=0.808 recalls=0 avg=0.620 source=memory/2026-04-21.md:3-5]

## Promoted From Short-Term Memory (2026-05-02)

<!-- openclaw-memory-promotion:memory:memory/2026-04-26.md:1:1 -->
- 2026-04-26 [score=0.812 recalls=0 avg=0.620 source=memory/2026-04-26.md:1-1]

## Promoted From Short-Term Memory (2026-05-03)

<!-- openclaw-memory-promotion:memory:memory/2026-04-28.md:3:5 -->
- 2026-04-28 [score=0.805 recalls=0 avg=0.620 source=memory/2026-04-28.md:1-2]

## Promoted From Short-Term Memory (2026-05-04)

<!-- openclaw-memory-promotion:memory:memory/2026-04-28.md:1:1 -->
- 2026-04-28 [score=0.812 recalls=0 avg=0.620 source=memory/2026-04-28.md:1-1]
