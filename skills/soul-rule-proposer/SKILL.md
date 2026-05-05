---
name: soul-rule-proposer
description: Use when the same failure mode keeps appearing in `reports/mistakes.md` and you suspect a SOUL.md rule is overdue. Triggers — "propose SOUL rule", "cluster mistakes", "soul-rule-proposer", "is there a recurring failure mode", or after a `mistake-loop-close` heartbeat surfaces 3+ closed mistakes that smell related. The skill clusters mistakes by symptom keywords and drafts a SOUL bullet stub (rule + **Why:** + **How to apply:**) for human review. It never edits SOUL.md.
---

# soul-rule-proposer

## When to reach for this

You notice — or a heartbeat nudges — that the same kind of failure has shown up in `reports/mistakes.md` more than twice. Examples that should fire this skill:

- Three+ entries about layer confusion (CC vs OpenClaw) with separate dates.
- Three+ entries about cron/notifier scripts firing real side effects on smoke tests.
- A reflect run flags "recurring symptom" and you want the cluster, not a guess.

If you only have one or two related mistakes, do not reach for this — single incidents earn a `feedback_*.md` memory, not a SOUL bullet. The threshold for SOUL is recurrence, not severity.

**Not for:** generating SOUL bullets from a single fresh mistake, retroactively codifying rules God already wrote, or auto-editing SOUL.md. The skill *proposes*; humans approve.

## How to invoke

```
bash scripts/soul-rule-proposer.sh
bash scripts/soul-rule-proposer.sh --min-cluster 4
```

Default `--min-cluster` is 3 (the brief threshold). Lower it only when you want to inspect the long tail of unique failure modes — that path produces stubs, not rules to ship.

The script reads `reports/mistakes.md`, parses every `### HH:MM —` entry, tokenizes the header symptom + `**Why wrong:**` block, drops a stopword list (common English + mistake-doc filler like "memory", "fix", "session"), and clusters by union-find when two entries share at least 2 non-stopword tokens.

Output goes to **stdout only**. The script never edits SOUL.md.

## How to interpret the clusters

For each cluster of size `>= MIN_CLUSTER` the script emits:

```
## Cluster: <auto-derived-name> (<N> entries)
Entries:
- <date>/<HH:MM> — <header>
- ...

Proposed SOUL bullet:
- **<one-line rule>.** **Why:** <inferred from "Why wrong" snippets>. **How to apply:** <inferred from "Durable fix" snippets>.
```

Read the proposal as a **starting draft**, not a finished rule. The cluster name is derived from the two most-frequent shared tokens, so it will often be ugly ("session-reflex", "split-artifact"); rewrite it. The Why/How snippets are truncated to 180 chars from the first member's blocks — they capture the right vocabulary but miss the cross-entry pattern that makes the rule worth writing.

Your job before sending the bullet to God:

1. Read all `<N>` entry bodies, not just the cluster header. The shared tokens may be coincidental.
2. Restate the rule in one declarative sentence — imperative voice, like the existing SOUL Meta-rules.
3. Tighten **Why:** to one sentence naming the concrete failure mode (e.g., "the OpenClaw CLI watchdog kills silent 600s turns"), not a paste from one entry.
4. Tighten **How to apply:** to a triggerable behavior (a verb + condition), not a fix description.

## Pre-condition rule

The script will refuse to propose a bullet for a cluster where any member lacks a `**Fix:**` line. Reason: SOUL rules codify *closed-loop* learning. If a mistake is still open, the durable fix may itself be the future rule — proposing now is premature. The script reports this as:

```
Pre-condition NOT MET: <N> entries in this cluster lack a Fix: line.
Skipping bullet proposal — only closed-loop clusters earn a SOUL rule.
```

When you see this, the right move is `mistakes-close` on the open entries first, then re-run.

## Human-review handoff

The skill output is a draft. To land a SOUL rule:

1. Run the script; capture the cluster + draft bullet.
2. Rewrite the bullet using the four steps above.
3. Show God the cluster (the entry list is the receipt) and the proposed bullet.
4. Wait for God to approve. Only then edit SOUL.md, by hand, in the Meta-rules section.

Hard rules from `scripts/lib/subagent-guardrails.md`:

- The skill must not modify `SOUL.md`, `AGENTS.md`, `IDENTITY.md`, `USER.md`, `TOOLS.md`, or `ROADMAP.md`.
- The script must not commit. Stdout-only.
- If the script ever auto-writes the proposal anywhere, that is a bug — report and revert.

## Empty-output is signal, not failure

If the script reports `no clusters of size >= N` at threshold 3, that is real signal: the mistakes.md tail is genuinely diverse and no single failure mode dominates. Do not lower the threshold to manufacture a rule. Tell God: "current mistakes do not cluster at >= 3 — failures are diverse, not a recurring single mode."

## Why a script, not a model call

Three reasons:

- **Determinism.** A token-overlap cluster on the same input file gives the same answer every run. A model call would drift, especially on truncation.
- **Auditability.** The cluster membership is grep-checkable; the proposal snippets are direct slices of the entry text. Human review can verify the script picked real entries, not hallucinated ones.
- **Cost.** This skill should be invokable from a heartbeat or cron without a token spend. Pure bash + awk; no Python, no SDK.

A semantic-similarity (embedding) clustering would catch related-vocabulary entries the keyword path misses. That is a worthwhile upgrade — but only after the keyword version has produced enough proposed bullets that we know which ones the lexical path is actually missing. Premature sophistication is its own failure mode.

## Eval

No fixture today. If clustering quality regresses (false-positive merges or missed obvious clusters), add a fixture under `evals/fixtures/soul-rule-proposer-*.json` that pins a known mistakes.md slice to expected cluster output.
