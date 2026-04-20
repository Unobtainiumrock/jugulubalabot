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
