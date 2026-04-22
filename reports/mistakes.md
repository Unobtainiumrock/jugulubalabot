# Mistakes — the anti-learning lane

Append-only. Newest first. For each: date, what I believed, the evidence
I had, what was actually true, why the belief was wrong, the durable fix
(memory pointer / eval fixture / commit).

This lane exists because silent correction breeds silent overconfidence.
Fixing a wrong memory in place erases the fact that I ever held it.
Recording mistakes here preserves the pattern so I can see my own
failure modes across time.

## Routing

| Type of mistake | Record here + | Also update |
|---|---|---|
| Memory I saved that was wrong | full entry below | edit/delete the memory file |
| Code I shipped that didn't work | full entry below | commit message of the fix |
| Confident claim to God that turned out false | full entry below | — |
| A rule I repeatedly violated | full entry below | `feedback_*.md` memory |

---

## 2026-04-21

### 06:28 — Ran `track2-checkin.sh` manually; it pushed a real Telegram

**What I believed:** Running `bash scripts/track2-checkin.sh` to gather
signal for a Track-3 readiness check would print stats to stdout.

**What's actually true:** It's a one-shot notifier that pushes via
`openclaw message send` — Telegram message 338 fired to God, claiming
the Track 2 check-in was live on day 2 of the 7-day window. Identical
pattern to `feedback_smoketest_vs_live_cron`: I have the rule, I didn't
apply it before invoking a cron-shaped script.

**Fix:**
1. This entry.
2. Header comment on `track2-checkin.sh` already flags one-shot; adding
   a `--dry-run` flag would make the rule enforceable, not memorized.
   Ticketed below as durable fix candidate.
3. **Resolved 2026-04-21 H1 overnight pass:** shipped `--dry-run` flag
   on `track2-checkin.sh`. Manual runs now default to live, but the
   escape hatch exists and the help text documents it.

### 05:05 — Silent stall: context 241% over budget, 0 compactions

**What happened:** Session ran from Wave-II capability work through
`/new` at 05:11. Final completed turn was a heartbeat alert about the
unfilled Hypotheses section in `reports/reflect-2026-04-20.md` at
05:18:29 UTC the prior cycle. After that: silence. Not a crash — a
stall. God had to poke with a diagnosis prompt to get a response.

**Root cause:** Context = 481k against a 200k budget (241% over), zero
compactions in the entire session. 94% cache hit rate kept cost flat
but doesn't help latency or hard limits. Each turn re-streamed ~453k
cached + 28k new — eventually something upstream (harness timeout,
gateway backpressure, or the model refusing to extend) gave up silently.

**Why wrong:** I had `scripts/budget-peek.sh` and explicit ORANGE-zone
monitoring guidance built *specifically* to catch this — and never ran
it during the session. The capability existed; the reflex didn't.

**Pattern:** Tools only pay off with *use*. Ownership of a capability
doesn't substitute for invoking it in the moment. This is the second
time a budget/cost capability has been present and unused at the moment
it was needed (see 08:35 entry 2026-04-20 on token-accounting latency).

**Fix:**
1. This entry.
2. Design robust `/new` process (session-clean.sh + SessionStart hook)
   so zombie transcripts can't accumulate silently — separate ask from
   God, tracked in the current conversation.
3. Consider a heartbeat task that calls `budget-peek.sh` and pushes
   when it crosses ORANGE, instead of relying on me to remember.
4. **Resolved 2026-04-21 H1 overnight pass:** item 2 shipped earlier
   (session-clean.sh SessionStart hook, commit 26466ed). Item 3 shipped
   now as `budget-peek-watch` task in `HEARTBEAT.md` — hourly peek, alerts
   on ORANGE/RED. Capability is now scheduled, not reflex-dependent.

### 05:10 — Claimed "no heartbeat means /new kills the old session"

**What I believed:** That `/new` cleanly terminates the prior session
and that checking `ps` is sufficient to confirm no zombies exist.

**What's actually true:** The `claude` CLI is re-spawned per turn with
`--resume <session_id>`, so there is never a long-lived CLI process to
"kill." Zombie state lives elsewhere:
- On-disk transcripts in `~/.claude/projects/**` accumulate forever.
- Gateway `sessions.json` grows (450KB observed) as it tracks per-channel
  state across many historical session IDs.
- Reset-archival (`*.jsonl.reset.<timestamp>`) is newer than most prior
  `/new` calls — so there's no way to count how many /news have happened.

**Why wrong:** I reasoned from OS process model (PIDs, kill signals)
when the actual state lives in gateway registry + on-disk transcripts.
Layer confusion again: CC layer vs OpenClaw gateway layer.

**Fix:** The "robust /new" design must treat session lifecycle as
state-file hygiene, not process management.

**Resolved 2026-04-21 H1 overnight pass:** same durable fix as 05:05
entry — `session-clean.sh` SessionStart hook (26466ed) manages the
state-file side of session lifecycle. Not process-killing; file-hygienic.

---

## 2026-04-20

### 09:20 — Confident claim: "no heartbeat mechanism exists"

**What I believed:** When God asked "is it some sort of heartbeat thing
that happens when you wake up each day," I answered "no, there isn't one —
it's just MEMORY.md + CLAUDE.md + system-reminders + my judgment."

**Evidence I had:** I reasoned from Claude Code's mental model (CC has no
heartbeat primitive) without checking if OpenClaw layers one on top.

**What's actually true:** OpenClaw has a first-class heartbeat mechanism —
scheduled agent turns (default `30m`, `1h` with OAuth), `HEARTBEAT.md`
workspace checklist, `tasks:` blocks with per-interval sub-prompts,
`isolatedSession` + `lightContext` for ~2–5K-token runs, `HEARTBEAT_OK`
ack contract. Confirmed via `docs.openclaw.ai/gateway/heartbeat`.

**Why wrong:** Exactly the CC-vs-OpenClaw layer confusion God flagged one
turn earlier. I answered from the wrong layer of the stack — confidently.

**Fix:** (1) this entry, (2) `HEARTBEAT.md` populated with real audit tasks
instead of the stub, (3) `reflect.sh` extended with OpenClaw primitive-usage
counts so underuse is measurable drift.

**Pattern to watch:** before answering "does X exist / does the system do
Y," always ask which layer before answering — CC, OpenClaw, or my scripts.
CC-layer reflex is the default failure mode.

### 08:35 — Confident claim: "turns are fresh" when budget-peek refreshes

**What I believed:** That `scripts/token-accounting.sh` refreshing
`turns/$DATE.jsonl` from transcripts gives budget-peek real-time cost.

**What's actually true:** Token accounting is as fresh as the last
transcript write from the Claude Code harness, which buffers. Numbers
can lag the current turn by ~1 turn. Close enough for "am I burning
cash?" checks; not close enough for enforcement.

**Lesson:** When describing latency guarantees, qualify with "best-effort,
~turn-grained" rather than implying real-time.

### 07:30 — gitignore negation via bare directory pattern

**What I believed:** `reports/` in `.gitignore` plus `!reports/learnings.md`
would let that one file through.

**Evidence I had:** Git docs mention negation; I reasoned from first
principles without testing.

**What's actually true:** Git does not descend into a fully-ignored
directory to evaluate negation patterns inside it. The parent must be
matched via a glob (`reports/*`) for `!reports/foo.md` to take effect.

**Why wrong:** Over-trusted my mental model of gitignore semantics
instead of running `git check-ignore -v`.

**Fix:** `.gitignore` → `reports/*` + `!reports/learnings.md`. Force-amend
as 959396c. Memory at `memory/` untouched because this was a one-shot
rule, not a recurring behavior pattern — lives here and in
`reports/learnings.md` 07:43 entry.

### 2026-04-22 00:47 UTC — committed without pushing, sat 2 min until God asked

**What I believed:** Commit complete, handoff done.

**Evidence I had:** `feedback_no_ask_workspace_commits.md` line 14
explicitly says "default to pushing unless there's a reason not to"
and the two commits (39c322d guards/fixtures/SOUL, 0de1961 reflect
sidecar) had nothing experimental. Yet I stopped at `git commit` and
returned control.

**What's actually true:** Commit≠ship. Master is not visible to God
(or GitHub, or any downstream reader) until pushed. God asked
"why were these not shipped" 90 seconds after the commits landed.

**Why wrong:** Exactly the failure mode I just committed to SOUL.md
in 39c322d under "Capability-exists ≠ reflex-fires" — the rule was
in memory, the reflex didn't fire. Old ask-before-push muscle memory
survived the 2026-04-21 pre-approval grant.

**Fix:** No memory edit (rule is correct). This entry is the signal.
If it recurs, promote to enforcement — e.g., a post-commit hook on
`/root/.openclaw/workspace` that auto-pushes master unless the commit
message contains `WIP` or `[no-push]`. One more occurrence = ship
the hook.

**Update 2026-04-22 04:40 UTC:** Hook shipped at
`.git/hooks/post-commit`. Pushes master after every commit unless subject
contains `WIP` / `[no-push]` or `OPENCLAW_NO_AUTOPUSH=1`. Log at
`reports/auto-push.log`. This closes the discipline-only gap.
