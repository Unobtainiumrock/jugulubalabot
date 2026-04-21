# Shared subagent guardrails

A stable set of invariants for any parallel-dispatch or delegated work in this
workspace. Reference this file from skills (e.g., `parallel-dispatch`) instead
of pasting the rules into every brief — so editing one file tightens guardrails
everywhere they apply.

Version: 1 (2026-04-21)

## Files that must not be modified by subagents

- `AGENTS.md`
- `SOUL.md`
- `IDENTITY.md`
- `USER.md`
- `TOOLS.md`
- `ROADMAP.md`

Reason: these are the agent's operating documents. Changes to them are
always an explicit, top-level conversation with the user — never a
side-effect of a subagent task. If a subagent proposes touching one,
the parent should stop and ask the user why.

## Billing / auth / model-provider

- No workarounds for billing errors (insufficient credits, 401/402/403
  responses, "quota" mentions). If you hit one, log the verbatim error
  and exit non-zero. Do not retry, do not swap providers, do not mock.
- No editing of `~/.claude/settings.json` auth fields, OpenClaw gateway
  config, or any credential material.

## Human-gated surfaces

- No auto-PR, no auto-delete, no auto-commit by subagents.
- No parsing of user replies to execute destructive actions — every
  "keep/drop"-style decision gets actioned in a later main-session turn,
  manually.
- Empty surfaces (no candidates, no digest rows) stay silent. Do not
  train the channel to ignore noise.

## Script conventions

- `set -uo pipefail` at the top of new shell scripts.
  Do not use `set -e` unless the script is tightly scoped and failure
  should genuinely abort — graceful degradation with warn-and-continue
  is usually better here.
- One-line summary on stderr at the end of a successful run
  (format: `<script-name>: <what happened>`).
- Log runs with structure to `state/<script>-log.jsonl` when the script
  has an external side-effect (Telegram push, PR, cron mutation).

## Reporting back to parent

Return under 400 words unless the brief explicitly asks for more.
Structure:

1. What you built (file paths + one-line purpose).
2. Smoke-test output (the specific items the brief asked for).
3. Any decision not pinned in the brief, with reasoning.
4. Blockers or surprises.

Do not commit. Do not open a PR. The parent reviews and commits.

## Parallelism

Subagents dispatched in parallel must touch disjoint files. The parent
pins the output schema up front so later-reading agents can target the
contract, not the implementation. If two agents genuinely need to
touch the same file, sequence them — or collapse them into one agent.

## Edge cases to flag, not work around

- Missing input files → warn, skip gracefully, keep going.
- Malformed input JSON → log the line number and skip, do not crash.
- Unexpected state (files with unknown schemas, branches with
  uncommitted changes, lock files held by other processes) → stop and
  report to parent. Investigate before overwriting.
