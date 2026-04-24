# Heartbeat — stable checklist for the OpenClaw scheduler

Runs on agent heartbeat cadence (default `30m`, `1h` with Anthropic OAuth).
If no task below finds anything actionable, reply exactly `HEARTBEAT_OK`
and stop — the token is stripped and the message dropped if the remainder
is ≤ `ackMaxChars` (default 300).

Layer: these tasks live in the **OpenClaw** layer. They are triggered by
OpenClaw's scheduler, not by Claude Code's hooks.

Kill switch: set `agents.defaults.heartbeat.every: "0m"` or delete these
tasks and leave the file header-only.

---

tasks:
- name: primitive-usage-drift
  interval: 24h
  prompt: |
    Read workspace `traces/<today-UTC>.jsonl`. Count invocations where
    `tool` starts with `mcp__openclaw__` OR tool is `Skill` and the class
    references `openclaw-skills:`. If total invocations for the day are
    >= 10 AND OpenClaw-native count is 0, alert with one concrete
    suggestion (which primitive for which observed pattern). Otherwise
    reply HEARTBEAT_OK.

- name: mistake-loop-close
  interval: 24h
  prompt: |
    Read `reports/mistakes.md`. If the newest entry is dated today or
    yesterday AND lacks a `Fix:` line or durable-fix pointer, alert with
    a one-line nudge naming the entry. Otherwise reply HEARTBEAT_OK.

- name: reflect-signoff
  interval: 24h
  prompt: |
    Run `bash scripts/reflect-signoff-alert.sh`. The script checks
    yesterday's review sidecar (`reports/reflect-<date>-review.md`)
    and, if missing, emits a Telegram message with inline buttons
    (👀 View hypotheses / ✅ Approve as-is / ⏭️ Skip) that route to
    the `reflect-signoff` plugin at `.openclaw/extensions/reflect-signoff/`.
    Cooldown + breadcrumb logic lives inside the script. Reply
    HEARTBEAT_OK — the script handles user-facing delivery itself.

- name: stale-scratch
  interval: 48h
  prompt: |
    Read `state/scratch.md`. If the `_Last updated:_` timestamp is older
    than 48h AND the file contains non-template content beyond the header,
    alert that the scratch notepad may be stale. Otherwise reply
    HEARTBEAT_OK.

- name: budget-peek-watch
  interval: 1h
  prompt: |
    Run `bash scripts/budget-peek.sh --risk`. If the first line starts
    with `Context-risk [ORANGE]` or `Context-risk [RED]`, alert with the
    full line so the active session knows to compact or back off.
    Otherwise reply HEARTBEAT_OK. Codifies 2026-04-21 05:05 mistake
    (silent stall at 241% context). The capability existed; the reflex
    didn't — this heartbeat is the reflex.

- name: claude-print-health
  interval: 24h
  prompt: |
    Run `bash scripts/claude-print-health.sh`. If the first line starts
    with `Claude-print-health [FAIL]`, alert with that first line only.
    Otherwise reply HEARTBEAT_OK. This keeps the benchmark / print lane
    observable so we notice auth, DNS, API reachability, or writable-state
    regressions before a baseline run silently burns time on timeouts.

- name: dreaming-bridge
  interval: 24h
  prompt: |
    Run `bash scripts/dreaming-bridge.sh`. If the first line starts with
    `Dreaming-bridge [YES]`, alert with that first line only. Otherwise
    reply HEARTBEAT_OK. This makes dreaming feed the self-evolving loop
    when the same recalled material keeps converging across days.
