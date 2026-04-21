---
name: parallel-dispatch
description: Use when a task naturally decomposes into 2+ independent units that can be built concurrently by subagents — new capability wave, multi-file scaffold, disjoint producer/consumer pieces. Pins output schemas up front, briefs agents from a shared guardrails file, runs them in parallel, reviews and commits in the parent.
---

# Parallel dispatch

## When to reach for this

You have 2+ units of work that:

- Touch disjoint files (or can be made to),
- Have a pin-able output contract (schema, file path, function signature),
- Don't need to see each other's code mid-flight.

Smoke test: could a competent colleague pick up each unit with the brief alone and finish without pinging you? If yes, dispatch. If no, sequence it — or collapse to one agent.

**Not for**: tight back-and-forth debugging, one-file edits, work where the right approach only becomes clear after the first piece lands.

## Procedure

1. **Write down the output contract for every unit before dispatching.** File paths, schemas, function signatures. Pinning the contract up front lets downstream agents target the interface, not the implementation — and stops you from having to reconcile three divergent designs after the fact.

2. **Check disjointness.** If two units would both edit the same file, merge them into one agent or sequence them. Parallel agents touching the same file = merge conflicts you'll resolve by hand.

3. **Draft one brief per unit.** Each brief is self-contained — the agent hasn't seen this conversation. Use the template below.

4. **Reference the shared guardrails file** from every brief: `scripts/lib/subagent-guardrails.md`. Don't paste the rules inline — the file is the source of truth and editing it tightens every future dispatch.

5. **Dispatch all agents in a single message** with multiple Agent tool-use blocks. `run_in_background: true` if you have other work to do while they run; foreground if their results gate your next move.

6. **Review each agent's return** in the parent. Verify the contract you pinned was met. Agents summarize intent, not reality — read the actual diff.

7. **Commit in the parent.** Subagents do not commit, do not open PRs. One parent review, one commit (or a stacked set), one push.

## Brief template

```
# Goal
<one sentence — what the agent is building and why it matters>

# Deliverable
<exact file path(s)>
<output schema or function signature, pinned>
<acceptance test: "running X should produce Y">

# Guardrails
Follow scripts/lib/subagent-guardrails.md. Key points for this task:
- <any task-specific addition>

# Smoke-test this before returning
<specific command(s) the agent must run and paste output for>

# Report back
<= 400 words. Structure per guardrails file.
```

## Anti-patterns

- **Vague goals.** "Investigate X and improve it" produces shallow, generic work. Brief like you would a colleague: what, why, what you've ruled out, what "done" looks like.
- **Shared-file dispatch.** Two agents editing the same file in parallel is a guaranteed merge conflict — or worse, silent overwrites.
- **No pinned contract.** If the schema isn't decided before dispatch, the agents will each invent one and you'll spend the savings reconciling.
- **Auto-commit from the agent.** Parent reviews. Parent commits. Always.
- **Trusting the summary.** An agent's "done" report describes intent. Read the diff.

## Failure modes to watch

- Agent stalls on a billing/auth error — per guardrails, it should log the verbatim error and exit non-zero. If it retries or swaps providers, stop and investigate.
- Agent proposes touching a protected operating doc (AGENTS.md, SOUL.md, IDENTITY.md, USER.md, TOOLS.md, ROADMAP.md) — stop and ask the user. Never a side-effect.
- Agent reports "done" but the deliverable file is empty or the smoke-test output is synthetic. Run the smoke test yourself.
