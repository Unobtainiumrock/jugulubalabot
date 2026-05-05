---
name: memory-curator
description: Use when reviewing recent daily logs for material that should graduate to durable MEMORY.md — the writer-half of the dreaming-bridge loop. Triggers on "curate memory", "promote daily logs", "memory-curator", "review memory candidates". Surfaces high-signal paragraphs from the last N days with rationale; the operator decides what to promote and edits MEMORY.md by hand.
---

# memory-curator

## When to reach for this

You are doing a memory-maintenance pass (per AGENTS.md § Memory Maintenance) and want to know which fragments from the last few days of `memory/YYYY-MM-DD.md` look durable enough to belong in `MEMORY.md`. The `dreaming-bridge` heartbeat task watches for cross-day convergence in *recall* signal but does not write — this skill is the writer-side counterpart that proposes promotions from *content* signal in the daily logs.

Reach for it when:

- A few days of activity have accumulated and `MEMORY.md`'s top-of-file curation is starting to feel stale.
- A heartbeat slot is open and you want a low-cost review pass.
- You just shipped a behavioral change and want to confirm whether the lesson belongs in the durable layer.

**Not for**: writing brand-new memories from scratch (just edit `MEMORY.md`), or for promoting from sources other than `memory/YYYY-MM-DD.md` daily logs.

## How to invoke

```
bash scripts/memory-curator.sh                  # default: last 14 days
bash scripts/memory-curator.sh --days 7         # narrower window
bash scripts/memory-curator.sh --since 2026-04-20  # explicit start date
```

The script is read-only. It prints candidate paragraphs to stdout and exits 0 even when there are no candidates. Empty output is the honest answer when nothing graduates — do not lower the bar to fill the surface.

## How to read the output

Each candidate prints as:

```
[N] memory/YYYY-MM-DD.md:<start>-<end>
    rationale: <which heuristic fired>
    preview:   <first 200 chars of the paragraph>
```

- `source path:line range` — where the paragraph lives in the daily log. Open that range in the daily file before deciding.
- `rationale` — which durable-signal heuristic fired (e.g. `contains 'rule:'`, `contains 'next time'`, `followed by **Why:**`).
- `preview` — the first 200 chars; intentionally short so you read the file, not the preview.

Already-promoted ranges are filtered out by matching `<!-- openclaw-memory-promotion:memory:<path>:<start>:<end> -->` markers in `MEMORY.md` (any byte-overlap with an existing marker counts as already-covered).

## Decision criteria

A candidate is **promotion-worthy** if it answers ANY of:

- A **rule** the agent has internalized that wasn't documented before. (Future-self needs to act on it without re-deriving.)
- A **decision with reasoning** that future-self will need. (Why-we-chose-X is durable; what-we-did is not.)
- A **reusable mental model** built today. (Generalizes past the immediate task.)

A candidate is **NOT promotion-worthy** if it is:

- Tactical execution detail — "ran command X, got output Y", commit hashes, bin counts. Lives in the daily log forever; never durable.
- Already codified — the candidate's content is already covered by an existing `feedback_*.md`, skill, eval fixture, or memory entry. Promoting again creates duplication and dilutes the index.
- Time-bound state — "waiting on X to land", "next session should wipe scratch", anything whose truth value flips in 48h. Daily-log only.

When in doubt, **don't promote**. `MEMORY.md` is curated wisdom, not a longest-tail index — better to skip a borderline entry than load it with redundancy.

## The manual MEMORY.md edit step

The script does not write to `MEMORY.md`. Promotion is a manual edit:

1. Open `MEMORY.md` and find or create the section header for today (`## Promoted From Short-Term Memory (YYYY-MM-DD)`).
2. For each candidate you want to promote, append:

   ```markdown
   <!-- openclaw-memory-promotion:memory:<source-path>:<start>:<end> -->
   - <distilled one-line takeaway, in your own words> [score=<N> recalls=<N> avg=<N> source=<source-path>:<start>-<end>]
   ```

   The distillation matters: the promoted line should be the **lesson**, not a copy of the daily-log paragraph. The marker preserves provenance; the prose is yours to shape.
3. Top-of-file curation: promote the most-reused durable items toward the top so they appear in main-session startup context. Drop entries that have been superseded.
4. Commit `MEMORY.md` with a clear message (`chore(memory): promote N entries from daily logs YYYY-MM-DD..YYYY-MM-DD`). The `daily-memory-promote-commit` cron also catches this lane if you forget.

## Heuristics (what the script looks for)

Durable signal is detected by either:

- A paragraph containing one of: `rule:`, `next time`, `from now on`, `I should`, `lesson learned` / `lessons learned`, `decision:`, `decided to`, `the rule is` (case-insensitive).
- A paragraph immediately followed by another paragraph beginning with `**Why:**` — the explicit-reasoning marker is a strong signal of a decision with attached rationale.

These are intentionally narrow phrase-matches rather than LLM-judged signal. Phrase matches are deterministic, free, and cheap to audit; the operator still makes the actual call. The cost of a false negative (a durable insight that happens to use no trigger phrase) is one extra heartbeat pass; the cost of a false positive (LLM-inflated noise) is bad memory hygiene that compounds.

## Guardrails

- The script is **read-only**. It never writes to `MEMORY.md`, the daily logs, or any other file. Output is stdout-only; the operator owns every promotion edit.
- Empty output is fine. Do not invent candidates to fill the surface.
- Do not run the script on directories other than `memory/`. Curated `dreaming/` artifacts and `heartbeat-state.json` are out of scope.

## Why a skill, not just an ad-hoc grep

Two reasons:

1. **Provenance filter.** Hand-grepping doesn't subtract already-promoted ranges; the script does. Without that, every pass surfaces the same paragraphs already absorbed.
2. **Reflex.** The dreaming-bridge already runs as a heartbeat watcher. Pairing it with a named writer skill makes "promote daily logs" a one-line operation instead of a multi-step recall.

## Eval

No fixture today. Add one (`memory-curator-respects-promoted-markers`) if a future regression shows the script re-surfacing already-promoted ranges.
