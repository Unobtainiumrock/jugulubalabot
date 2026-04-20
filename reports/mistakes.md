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
