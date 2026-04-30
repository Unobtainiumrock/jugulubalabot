---
name: eval-fixture-author
description: Use when noticing a reflex gap (a behavior the agent should have but doesn't) that should be locked in as an eval fixture. Authors the JSON fixture, registers it in eval-notify.sh + eval-review-bootstrap.sh's fixture_summary/bucket tables, and runs the new fixture once as a smoke test. Replaces the multi-step Write-fixture → grep-summaries → edit-summaries → run-eval pattern with a guided one-shot.
---

# eval-fixture-author

## When to reach for this

You notice a behavior the agent should have but doesn't, AND you want to lock it in as a regression-detector. Examples:

- "I just answered the capability question without naming the layer split" → fixture
- "I just used Write+chmod instead of mkscript" → fixture
- "I just structured a plain-English question into bullet tables" → fixture

The trigger is recognising the *shape of the gap*, not just the surface message. If the gap repeats, write the fixture before doing anything else — otherwise it doesn't survive the next session.

**Not for**: one-off mistakes that aren't a behavior pattern, fixtures testing harness internals, or fixtures that depend on session state we can't reproduce in a fresh `claude -p` call.

## How to use

```
bash scripts/eval-fixture-author.sh <slug> '<one-line summary>' '<bucket>'
```

- `slug` — kebab-case fixture name. Becomes `evals/fixtures/<slug>.json`. Must not exist yet.
- `summary` — human-readable one-liner of the regression mode (used in `fixture_summary` tables of `eval-notify.sh` and `eval-review-bootstrap.sh`).
- `bucket` — one of `workflow`, `judgment`, `wording`, `other`. Maps to the standard fixture buckets.

The script:

1. Drops a fixture skeleton at `evals/fixtures/<slug>.json` with `prompt`, `graders[regex_positive|regex_negative|llm_judge]`, and `timeout_seconds` placeholders.
2. Registers the slug + summary in `scripts/eval-notify.sh::fixture_summary()`, `scripts/eval-review-bootstrap.sh::fixture_summary()`, and the corresponding `fixture_bucket()` tables.
3. Prints next steps: edit the prompt + graders, then `FIXTURES=<slug> bash evals/run.sh` to verify.

Edit the placeholders before relying on it — the skeleton is intentionally a stub that fails until the prompt is real.

## Anatomy of a fixture

```json
{
  "name": "<slug>",
  "description": "<what regression this guards against; written for a future-you who's confused>",
  "prompt": "<the prompt that elicits the behavior — short, no setup>",
  "timeout_seconds": 180,
  "graders": [
    {"type": "regex_positive", "patterns": ["<phrase that MUST appear>"]},
    {"type": "regex_negative", "patterns": ["<phrase that MUST NOT appear>"]},
    {"type": "llm_judge", "rubric": "<PASS/FAIL contract for the judge>"}
  ]
}
```

- **regex_positive / regex_negative** are cheap and deterministic. Use them when the contract is "the answer must contain X" or "the answer must not contain Y".
- **llm_judge** is for shape contracts that regex can't capture ("the answer must structure both layers explicitly"). Keep the rubric short and binary.
- Graders are AND'd together. `prefer-mkscript` and `layer-confusion` both use all three layers — that's a good template.
- **timeout_seconds** defaults to 180. Bump for fixtures that need network or full SOUL.md read; one fixture (`orange-budget-triggers-peek`) hit exactly 180s with empty stdout — set to 240+ if your prompt is the kind that triggers tool-heavy work.

## Two duplicated tables (known caveat — DRY follow-up)

`eval-notify.sh` and `eval-review-bootstrap.sh` both maintain their own `fixture_summary()` / `fixture_bucket()` tables. The author script updates both, but if you edit by hand, keep them in sync. A future Improve candidate should DRY them into a single source.

## When NOT to use

- **Modifying an existing fixture** → use `Edit` directly on the JSON.
- **Adding a new bucket** → edit `fixture_bucket()` by hand. The author script picks from the four existing buckets only.
- **Mass authoring (>3 at once)** → batch-author by hand. The skill is optimised for one-at-a-time.

## Smoke test

After authoring, the next move is always:

```
FIXTURES=<slug> bash evals/run.sh
```

A green run on the new fixture means the regex/judge contracts match the agent's current behavior — useful baseline. A red run means you've already locked in the regression.
