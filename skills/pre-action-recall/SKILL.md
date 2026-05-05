---
name: pre-action-recall
description: Use when noticing a "I had the rule, didn't apply it" failure mode in your own behavior. This skill installs a non-blocking PreToolUse hook that surfaces relevant prior mistakes and feedback memories *before* you commit to a tool call. Closes the discipline-only failure class. Trigger phrases — "pre-action recall", "intent hook", "fire on intent not output", "intercept reasoning like pre-bash-guard intercepts commands".
---

# pre-action-recall

## When this skill exists

Most workspace failures share a shape: the rule existed in MEMORY.md or SOUL.md, the agent didn't apply it. `pre-bash-guard` solves this for command-level anti-patterns by *intercepting* — but it only catches regex-shaped command patterns. Many real failures are semantic (editing SOUL.md without a fixture, dispatching a "loop until working" task in the parent turn, smoke-testing a live-cron script without `--dry-run`).

This hook fires on tool *intent*, not on tool output. It greps tool input against a curated index of past lessons and emits `additionalContext` so the model sees the recall as a system reminder before the call lands.

## Architecture

Three pieces, each with a single responsibility:

1. **`scripts/build-recall-index.sh`** — emits `state/recall-index.tsv`. Each row is `<pattern>\t<kind>\t<source>\t<rule>`. Patterns are case-insensitive substrings, hand-curated for high precision plus auto-extracted mistake headers from `reports/mistakes.md`.

2. **`scripts/hooks/pre-action-recall.sh`** — PreToolUse hook. Reads tool name + input from stdin, walks the index, emits `{"hookSpecificOutput": {"hookEventName": "PreToolUse", "additionalContext": "RECALL — ..."}}` when patterns match.

3. **`/root/.claude/settings.json`** PreToolUse hook entry — wires the script in alongside the existing `trace.sh pre` and `pre-bash-guard.sh` hooks.

## How it stays signal, not noise

- **Read-only tools skipped.** `Read | Glob | Grep | TodoWrite | ToolSearch | NotebookRead` never trigger recall. Recall only fires on write/intent tools (`Bash`, `Edit`, `Write`, `Skill`, `Agent`, `Task`, `WebFetch`).
- **Per-session dedup.** Each pattern fires at most once per session; the hash is recorded in `state/recall-fired.txt` and cleared on session start by `session-clean.sh`.
- **Cap at 2 hits per call.** A single tool call surfaces at most two recalls. More than that is noise pollution.
- **Curated patterns, not fuzzy matching.** The index is a hand-edited TSV. False positives are worse than false negatives — better to miss a recall than to fire on every fourth tool call.
- **Always non-blocking.** The hook exits 0 in every code path. It cannot prevent a call; it can only inform.

## Tuning the index

When a new failure pattern emerges:

1. Decide if `pre-bash-guard` could catch it as a regex anti-pattern. If yes, add it there instead.
2. If not, append a row to `scripts/build-recall-index.sh`'s curated section. Pattern field = a substring an agent would actually type. Rule field = the one-line lesson.
3. Re-run `bash scripts/build-recall-index.sh`. Smoke-test by piping a synthetic tool-input JSON into the hook script.

When a recall fires too often without changing behavior:

- Either the rule isn't actionable enough — sharpen it.
- Or the pattern is too broad — narrow it.
- Or the lesson is internalized — remove the row.

## Refresh cadence

The index is rebuilt:
- Manually after editing `build-recall-index.sh`.
- Automatically by `SessionStart` if the auto-build hook is wired (recommended). The current setup rebuilds only on demand; the index file is checked into git so a fresh session has it from the start.

`reports/mistakes.md`-derived rows are pulled fresh each rebuild — the most recent 10 entries become soft recalls keyed on header keywords. New mistakes get coverage on the next index rebuild without manual curation.

## Kill switches

- **`OPENCLAW_RECALL_OFF=1 <bash command>`** — per-call bypass for Bash. Use when a smoke test of recall behavior would otherwise self-trigger.
- **`touch state/.recall-off`** — session-wide bypass. The hook short-circuits to `{}` immediately. Remove the file (or session-clean does it) to re-enable.

## Audit trail

Every fired recall is logged to `state/recall-log.jsonl` with `ts`, `tool`, `kind`, `source`, `rule`. Useful for:
- Confirming the hook is actually firing in real sessions.
- Spotting recalls that fire repeatedly but never change behavior — those rules need sharpening.
- Verifying the per-session dedup is working (a single hash should appear at most once per `session_id`).

## When NOT to use this hook

- **You haven't observed the discipline-only failure mode yet.** Don't pre-build for hypothetical patterns; let real mistakes drive the index.
- **The pattern is regex-catchable.** `pre-bash-guard` is the right substrate for command-shape rules. This hook is for semantic patterns the regex guard can't reach.
- **The rule changes per-task.** This hook is for stable rules that apply across many sessions. One-off task-specific rules belong in the conversation, not the index.

## Eval fixture

Add a fixture later if regressions show recalls firing without effect or recalls being missed where they should fire. The hook is observable via `state/recall-log.jsonl`, so eval prompts can exercise the index and grade against the log.
