---
name: mistakes-close
description: Use right after shipping a fix for a mistake recorded in `reports/mistakes.md` that lacks a `Fix:` line. Appends a `Fix:` pointer (commit hash, fixture path, memory file, or `feedback_*.md` slug) to the most recent open entry, so silent correction doesn't breed silent overconfidence. Closes the loop the `mistake-loop-close` heartbeat task watches for.
---

# mistakes-close

## When to reach for this

You just shipped something that fixes a `reports/mistakes.md` entry. The entry's body is intact (don't rewrite history) but it has no `Fix:` line. The `mistake-loop-close` heartbeat task (`HEARTBEAT.md`) already nudges when this happens within 24h — this skill is the closing reflex on the producer side, so the nudge stays unfired in the steady state.

Triggers:

- A commit lands that resolves a known mistake (the commit message often references the date or symptom).
- An eval fixture is authored that locks in the corrected behavior — `Fix:` should point at the fixture path.
- A `feedback_*.md` memory is added to MEMORY.md to codify the rule — `Fix:` should point at the slug.

**Not for**: mistakes still under investigation, mistakes whose fix is "do nothing" (write that explicitly as `Fix: no-op — root cause was external`), or rewriting historical mistake bodies.

## How to use

1. Find the open entry. Open mistakes are entries lacking a trailing `**Fix:**` line:
   ```
   Grep tool — pattern: "^### \d{2}:\d{2}", path: reports/mistakes.md
   ```
   Then read the section to confirm `Fix:` is absent.

2. Append a `Fix:` line under the entry body, before the next `### ` header. Format:

   ```markdown
   **Fix:** <commit-hash> — <short subject>; durable: <pointer>
   ```

   Where `<pointer>` is one of:

   - `evals/fixtures/<slug>.json` — fixture catches the regression
   - `MEMORY.md → feedback_<slug>.md` — codified rule
   - `scripts/<name>.sh` — automation that prevents recurrence
   - `SOUL.md § <section>` — answer-contract update
   - `no-op — <reason>` — when the right answer is intentional inaction

3. Commit the `Fix:` line as a follow-on to the actual fix commit, or include it in the same commit if the fix is workspace-local.

## Output contract

The skill is done when:

- The targeted mistake entry has a `**Fix:**` line with a commit hash and a durable pointer.
- The pointer resolves to something real (file exists, commit exists, slug is in `MEMORY.md`).
- The next `mistake-loop-close` heartbeat will not flag this entry.

## Why a skill, not just a memory

The discipline is in `MEMORY.md` and `SOUL.md`, but the *reflex* of writing `Fix:` at the right moment kept missing. The heartbeat catches the omission after the fact; this skill closes it on the same turn the fix lands.

## Eval

No fixture today. Add one (`mistake-fix-line-on-close`) if regressions show this skill being skipped after fix commits.
