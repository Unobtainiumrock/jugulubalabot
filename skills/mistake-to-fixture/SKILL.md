---
name: mistake-to-fixture
description: Use when a fresh entry just landed in `reports/mistakes.md` and the corresponding behavior fix has NOT yet shipped (no SOUL.md / MEMORY.md edit, no commit). Converts the mistake into a failing eval fixture via `eval-fixture-author.sh` so the regression is locked in BEFORE the rule is codified — the test must fail today and only pass once the fix lands. Trigger phrases: "scaffold fixture from mistake", "lock this in as a fixture", "mistake-to-fixture", "turn that mistake into a fixture", "regression-test the mistake first".
---

# mistake-to-fixture

## 1. When to reach for this

Fire this skill when ALL THREE conditions hold:

- A fresh `### HH:MM — <symptom>` entry exists in `reports/mistakes.md` with `What I believed` / `What's actually true` populated.
- The behavior fix is **not yet shipped** — no SOUL.md edit, no `feedback_*.md`, no commit closing the loop.
- The regression is the kind that would re-fire on a future `claude -p` call given the right prompt (i.e., session-state-independent).

If the fix has already shipped, you're past the lock-in window — use `eval-fixture-author` directly and skip the mistakes.md plumbing. If the mistake is one-off (not a behavior pattern), don't author a fixture; let the entry stand on its own.

## 2. Procedure

Map the mistakes.md entry onto the fixture pieces:

| mistakes.md field | Fixture piece |
|---|---|
| `### HH:MM — <symptom>` heading | `slug` (kebab-cased, see §3) and `summary` (one-liner) |
| `What I believed` | the prompt — phrase it so a fresh agent would be tempted into the same wrong belief |
| `What's actually true` | `regex_positive` patterns (phrases the right answer must contain) |
| `What I believed` keywords | `regex_negative` patterns (the wrong-answer fingerprint) |
| `Why wrong` | `llm_judge` rubric — short PASS/FAIL contract describing the shape the answer must have |
| Mistake category (see §4) | `bucket` |

Then:

```
bash scripts/eval-fixture-author.sh <slug> '<summary>' <bucket>
```

Edit the resulting `evals/fixtures/<slug>.json`, replacing the four TODO fields with the mappings above. `layer-confusion.json` is a good three-grader template.

## 3. Slug derivation rule

Take the symptom phrase from the `### HH:MM — <symptom>` heading. Lowercase, strip punctuation, replace whitespace with `-`, cap at six words. Drop filler words ("the", "a", "got", "just"). Examples:

- `### 07:02 — Took an "aggressively loop" instruction in-line and got watchdog-killed` → `aggressive-loop-in-parent-turn`
- `### 09:20 — Confident claim: "no heartbeat mechanism exists"` → `heartbeat-absence-claim`
- `### 19:20 — Asked for pasted artifacts before checking the artifact path` → `check-artifact-before-asking`

The slug must be unique under `evals/fixtures/` — `eval-fixture-author.sh` exits 2 if the file already exists.

## 4. Bucket selection

Pick by the mistake's *type*:

- **workflow** — review/process discipline broken. *Example: skipping a review step, asking for paste before checking files.*
- **judgment** — operator judgment under constraints. *Example: layer confusion, running a one-shot script that fires Telegram, looping in the parent turn instead of a subagent.*
- **wording** — answer shape or phrasing. *Example: dense bullets when plain English was asked, jargon-default, blank no-op hypothesis.*
- **other** — doesn't fit the above three. Use sparingly; force-fit one of the first three when plausible.

## 5. Smoke test (the inversion)

```
FIXTURES=<slug> bash evals/run.sh
```

**Expected: RED.** The fixture exists precisely because current behavior fails the contract. A green run on first authoring is the warning sign — it means the prompt didn't actually trigger the regression, or the graders are too loose. Tighten the prompt (make it more like the original failure context) or sharpen the graders (regex_negative on the wrong-answer fingerprint) until the fixture fails. Only then is the regression genuinely captured.

Once the SOUL.md / MEMORY.md fix ships, the same command should flip GREEN — that's the loop closing.

## 6. Hand-off to `mistakes-close`

After the fixture lands AND the SOUL fix follows, the mistakes.md entry needs a `Fix:` line. Use the `mistakes-close` skill; the durable pointer is the fixture path:

```
**Fix:** <commit-hash> — <subject>; durable: evals/fixtures/<slug>.json
```

The `mistake-loop-close` heartbeat will then stop nagging this entry. The fixture's red-to-green transition is the proof that the rule actually works in practice, not just on paper.

## When NOT to use

- Fix already shipped → `eval-fixture-author` directly.
- Mistake is one-off (not a behavior pattern) → no fixture.
- Regression depends on session state a fresh `claude -p` call can't reproduce → no fixture.
- Mass authoring from a backlog of old mistakes → batch by hand; this skill is one-at-a-time.
