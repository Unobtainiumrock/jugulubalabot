---
name: backlog-triage
description: Use when you need to triage backlog, surface stale backlog items, run backlog-triage, or reconcile backlog. Wraps `scripts/backlog-reconcile.sh` (resolved-but-still-open) and adds a trace-activity cross-reference (active in traces, stale with no activity, or stalled-doing). Output is human-gated — never auto-closes items.
---

# backlog-triage

## When to reach for this

- Heartbeat-style backlog hygiene — periodic check that the registry in `backlog.jsonl` still matches reality.
- Before any sprint-style planning pass — clear out items that already shipped or have gone cold so the working set reflects real state.
- After a wave of commits — code may have resolved items that the registry still lists open.
- On a `triage backlog` / `stale backlog` / `reconcile backlog` instruction.

## What it does

Two complementary checks, run together:

1. **Reconcile** (`scripts/backlog-reconcile.sh`, no `--apply`) — finds open IDs that overnight reports, learnings, or recent commits already mark as resolved. Conservative; prefers nag over false-close.
2. **Trace cross-reference** (the new triage step) — for each item still listed open/doing in `backlog.jsonl`, grep the last 14 days of `traces/*.jsonl` for the 6-char ID:
   - **Active in traces**: ID appears in `input_hash` or `class` fields → "active (last activity: <date>)".
   - **Stale**: created >14d ago AND no trace mention → "stale: open >14d, no trace activity".
   - **Stalled**: status is `doing` AND most recent trace mention is >7d old → "stalled: doing but no recent activity".

## How to run

```
bash scripts/backlog-triage.sh           # default: 14-day trace window
bash scripts/backlog-triage.sh --days 30 # widen window
```

Output is structured into four markdown sections:

- `## Resolved-but-open (from reconcile)` — pasted from `backlog-reconcile.sh`.
- `## Active in traces` — open IDs that show up in recent traces (still alive).
- `## Stale (no activity, old)` — open IDs >14d with no trace echo.
- `## Stalled (doing, idle)` — `doing` IDs whose last trace mention is >7d old.

Exit code is always 0 — this is a reporting tool.

## How to interpret the output

- **Resolved-but-open**: high-confidence close candidates. Verify the evidence pointer (commit / overnight report) actually proves the work landed, then close manually with `bash scripts/backlog.sh done <id>` and a note pointing at the evidence.
- **Active in traces**: working as intended. No action.
- **Stale**: ask whether the item is still wanted. If yes, leave a `note` explaining why it's not moving. If no, `drop` it with a reason.
- **Stalled (doing)**: the item is claimed but quiet. Either resume it or revert to `open` so it's clear nobody is on it.

## Guardrail: human-gated close

The script never passes `--apply` to `backlog-reconcile.sh` and never mutates `backlog.jsonl`. Closes happen in a follow-up turn through `scripts/backlog.sh done <id>` (with a `note` capturing the evidence). This is intentional — auto-close has historically false-positived on items whose commit message coincidentally name-matches an ID prefix.

## Why a skill, not just the script

The reconcile script existed but was invisible at skill-listing time, so the pattern wasn't reached for during planning. This skill surfaces both the existing reconcile flow and the new trace-activity check under a single `triage backlog` trigger — so the discipline is one tool call away rather than buried in `scripts/`.
