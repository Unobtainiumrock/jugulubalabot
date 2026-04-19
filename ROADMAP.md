# ROADMAP — Phase 2: Self-Evolution

**Status:** deferred. Tai should collect signal but not act on this yet. When God decides it's time, this doc is the starting point for wiring the loop.

## Intent

Turn Tai into a self-improving system along two axes:

1. **Agentic improvement** — per *Autogenesis: A Self-Evolving Agent Protocol* (Wentao Zhang, arXiv:2604.15034). Two-layer protocol: RSPL (prompts/agents/tools/env/memory as versioned resources) + SEPL (closed-loop operator algebra: Reflect → Select → Improve → Evaluate → Commit).
2. **Model improvement** — per God's `autoresearch` repo (https://github.com/Unobtainiumrock/autoresearch). Out of scope for the single-agent loop; relevant at the research-output layer.

## Instrumentation (prerequisite)

Before any loop runs, we need trace data. Every skill invocation should log:

- `timestamp`, `session_id`, `skill_name`
- `input_shape` (hash + rough class)
- `success` (bool), `duration_ms`
- `bin` (task taxonomy category; may be assigned retroactively)

Storage: JSONL, daily rotation, under `workspace/traces/YYYY-MM-DD.jsonl`.

Target ~100+ invocations before the first reflection pass has enough signal to bin into a real taxonomy.

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

## When to activate

Tai should nudge God to activate Phase 2 when any of:

- ≥ a week of active daily use
- ≥ 100 skill invocations logged
- A repeated pain pattern visible to both parties

Do not activate unilaterally. Activation is an explicit conversation and an explicit cron-wiring step.
