# ROADMAP — Phase 2: Self-Evolution

**Status:** Track 1 (Evaluate gate) shipped 2026-04-19 (commit `2f61cb3`, re-authored `942a0d4`). Tracks 2–4 deferred until signal accumulates. See "Phased activation plan" below for triggers and sequencing.

## Intent

Turn Tai into a self-improving system along two axes:

1. **Agentic improvement** — per *Autogenesis: A Self-Evolving Agent Protocol* (Wentao Zhang, arXiv:2604.15034). Two-layer protocol: RSPL (prompts/agents/tools/env/memory as versioned resources) + SEPL (closed-loop operator algebra: Reflect → Select → Improve → Evaluate → Commit).
2. **Model improvement** — per God's `autoresearch` repo (https://github.com/Unobtainiumrock/autoresearch). Out of scope for the single-agent loop; relevant at the research-output layer.

## Instrumentation (LIVE as of 2026-04-19)

Trace data collection is wired. Every tool call (not just skills) produces one JSONL entry in `workspace/traces/YYYY-MM-DD.jsonl` with:

- `ts` (ms precision, UTC)
- `session_id`, `tool`
- `class` — rough shape: Bash=first-token, Skill=skill-name, Read/Write/Edit=ext, Grep=simple|complex, etc.
- `input_hash` (12 hex chars, sha256 of canonicalized `tool_input`)
- `success` (bool), `duration_ms` (null if PreToolUse didn't fire)
- `bin` (null; reserved for retroactive taxonomy)

**Wiring:**
- `.claude/settings.json` — PreToolUse / PostToolUse / PostToolUseFailure hooks, all async.
- `scripts/trace.sh` — writer. Modes: `pre` (timestamp sidecar) / `ok` / `fail`.
- `scripts/trace-summary.sh [YYYY-MM-DD]` — daily rollup (counts, class breakdown, success rate, p50/p95 duration).
- Sidecars live under `workspace/state/trace-inflight/` and are consumed on post.

Target: ~100+ invocations before the first reflection pass has enough signal to bin into a real taxonomy.

## Nightly batch (cron)

- Schedule: `openclaw cron` at 03:00 UTC.
- Read: yesterday's traces + current SOUL/TOOLS/IDENTITY/skill files.
- **Reflect:** LLM pass over traces to produce hypotheses about gaps, repeated failures, inefficiencies.
- **Select:** propose concrete edits (prompt rewrites, new skill scaffolds, deterministic-replacement candidates). Use GA-style variant generation (God's `genetic-algorithms` repo) for multi-candidate proposals at the Select step.
- **Improve:** apply candidates to a git branch (workspace is already a git repo).
- **Evaluate:** run the candidate against a held-out eval set.
- **Commit:** merge only if evaluation passes; otherwise rollback. Git provides lineage + rollback.

## Weekly report (cron)

- Schedule: Sunday 06:00 UTC.
- Output: `workspace/reports/week-YYYY-WW.md`.
- Sections:
  1. Knowledge gaps — tasks that failed repeatedly this week.
  2. New skills/capabilities created by the nightly loop.
  3. Success rate of those skills on subsequent invocations.
  4. Token-burn → deterministic conversion candidates.
  5. Evolution proposals rejected at Commit, and why.

## Token-burn → deterministic principle

When a task pattern appears >N times (N TBD empirically, start ~5) and is structurally amenable to a deterministic function, propose converting it. Once approved and written, the deterministic path becomes the primary; the LLM path becomes the fallback.

## When to activate the Reflect loop

Instrumentation is live — signal is accumulating. Tai should nudge God to activate the nightly Reflect→Select→Improve→Evaluate→Commit loop when any of:

- ≥ a week of active daily use
- ≥ 100 tool invocations logged (check: `scripts/trace-summary.sh`)
- A repeated pain pattern visible to both parties

Do not activate unilaterally. Activation is an explicit conversation and an explicit cron-wiring step.

## Phased activation plan (Tracks 2–4)

Track 1 (Evaluate gate) is done: `evals/run.sh`, 7 seed fixtures, `scripts/eval-notify.sh` for Telegram regression alerts. The remaining tracks are sequenced below so future sessions know what to do when signal lands.

### Track 2 — Signal accumulation (passive, this week)

- Stub `scripts/reflect.sh` — reads yesterday's traces + SOUL/TOOLS/skills, writes `workspace/reports/reflect-YYYY-MM-DD.md`. Runnable manually; doesn't activate anything yet.
- Define `bin` taxonomy for traces. Currently every row has `bin: null`. Enumerate bins (e.g. `file_ground`, `external_fetch`, `memory_update`, `self_modify`, `agent_spawn`) and update `scripts/trace.sh` to classify on write.
- Grow eval fixtures from real friction — every DM screw-up becomes a fixture. Target: 15–20 fixtures by mid-week-2.
- Normal daily usage accumulates traces. Target: ≥100 invocations before first Reflect pass.

### Track 3 — Activation trigger (fire only when ALL true)

Before nudging God to activate, ALL of:

- ≥100 tool invocations logged (`scripts/trace-summary.sh`)
- ≥1 week of active daily use since 2026-04-19
- ≥1 repeated pain pattern visible (same failure or inefficiency 3+ times)
- `reflect.sh` stub exists and produces a readable report
- `bin` taxonomy in place (non-null bins on recent traces)

When all fire, the first manual Reflect pass runs:

1. God + Tai review `reports/reflect-<date>.md` together.
2. Identify top 3 hypotheses about gaps/inefficiencies.
3. Convert the clearest token-burn candidate to a deterministic script.
4. Schedule nightly `eval-notify.sh` via `openclaw cron` (regression alerts only, not the full loop yet).

### Track 4 — Full loop activation (week 2+, only after Track 3 stable)

- Wire **Select:** GA-style variant generation (pattern: God's `genetic-algorithms` repo). For each hypothesis, produce N candidate edits.
- Wire **Improve:** each candidate lands on branch `sepl/<date>-<hypothesis>`. Evals run via the existing harness. Pass → auto-merge to master. Fail → auto-rollback.
- Schedule full nightly cron at 03:00 UTC: Reflect → Select → Improve → Evaluate → Commit.
- Wire weekly report: `reports/week-YYYY-WW.md` — skills created, proposals rejected at Commit, token-burn conversions shipped.

Cross-references: SOUL.md line 33 (self-modification rules), commit `2f61cb3`/`942a0d4` (Evaluate gate), `evals/README.md` (harness usage).
