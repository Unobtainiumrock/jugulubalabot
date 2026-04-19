# Grading spec

Each fixture is one JSON file in `fixtures/`:

```json
{
  "name": "...",
  "description": "why this fixture exists — link to SOUL.md line or the incident that prompted it",
  "prompt": "...",
  "graders": [ { "type": "<grader_type>", ...args } ]
}
```

A fixture **passes** only if every grader passes. Any grader failure fails the fixture.

## Grader types

### `regex_negative`
Response stdout must NOT match any of the patterns. Case-insensitive extended regex (grep -iE).

```json
{"type": "regex_negative", "patterns": ["Great question", "happy to help"]}
```

### `regex_positive`
Response stdout must match ALL of the patterns.

```json
{"type": "regex_positive", "patterns": ["Paris"]}
```

### `response_max_chars`
Response stdout length ≤ `max`.

```json
{"type": "response_max_chars", "max": 250}
```

### `tool_sequence_contains`
The trace rows produced by this fixture's `claude -p` child must contain at least one row matching `tool` (and optional `class`). Time window is the fixture's run start/end. `tool` accepts either a string or an array of strings (OR semantics).

```json
{"type": "tool_sequence_contains", "tool": "Bash", "class": "wc"}
{"type": "tool_sequence_contains", "tool": ["Read", "Grep", "Glob"]}
```

### `llm_judge`
Semantic grader. Spawns a fresh `claude -p` with the response and a rubric, asks for a PASS/FAIL verdict. Catches tone drift, hollow proposals, and semantic violations that regex can't see. Cost: +1 `claude -p` per fixture.

```json
{
  "type": "llm_judge",
  "rubric": "The response must propose a specific deterministic mechanism (name a tool, script, or cron expr) AND defer the decision to the user. Both must be true."
}
```

Rubric tips:
- End with explicit criteria: "Answer PASS only if both X and Y are present."
- Anchor to concrete artifacts ("must name a cron expression", "must include a sample filename").
- Avoid vague words like "good" or "appropriate" — graders have to be mechanical.

## Adding a grader type

Extend the `case` block in `run.sh`. Keep them composable — a fixture can stack several.

## Principles

- **Grow from real friction.** A grader that never fires is dead weight; a fixture born from a screw-up earns its keep.
- **Read-only prompts.** Fixtures should not mutate workspace state. If you need to test write behavior, sandbox the target.
- **Fresh session per fixture.** Matches how Tai is actually used (Telegram cold starts).
