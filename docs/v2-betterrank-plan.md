# V2 pruning signal — BetterRank port (deferred)

## Status

**Deferred.** V1 ships today (2026-04-20). V2 fires automatically when
`scripts/v2-readiness-check.sh` detects the codebase has outgrown the
bash-only stand-in. Until then, do not port BetterRank — it would be premature.

## What V1 ships (the baseline you'll replace)

| Layer | Artifact | Cadence | Script |
|---|---|---|---|
| 1. Usage heat | `state/file-heat.jsonl` (per-file `heat`, `touches_total`, `last_touched`) | nightly | `scripts/heat-counter.sh` |
| 2a. Structural signal (bash v1) | `state/bash-callgraph.json` (edges + per-node `fan_in`/`fan_out`) | weekly | `scripts/bash-callgraph.sh` |
| 3. Surface (deferred)           | weekly Telegram "keep/drop" digest | manual | TBD |

Decay: `heat = 0.95 * prior + today_touches` (~14d half-life).
Input source: `traces/<date>.jsonl`, field `.paths` (populated by `scripts/trace.sh`
since 2026-04-20).

## Why V1 is a stand-in, not a finish

Layer 2a captures structural importance *within bash only*: A calls B via a
literal `scripts/B.sh` substring. It doesn't know:

- Python/TS/JS imports (tree is ~100% bash today; this is why V1 is OK).
- Transitive importance (PageRank-style).
- Module re-exports, dynamic imports, path aliases.

When the tree grows into JS/TS/Python, `bash-callgraph.json` will under-count
real importance — and a file can score "low centrality" in V1 while being a
heavily-imported Python module. That's the failure mode V2 fixes.

## V2 trigger conditions

`scripts/v2-readiness-check.sh` runs nightly and fires a one-shot Telegram
reminder when **any** holds:

- **(a)** `>= 25` source files under the workspace with extension
  `.py|.ts|.tsx|.js|.jsx`, or
- **(b)** `>= 100` tracked files in `state/file-heat.jsonl` **and** the non-bash
  fraction is `>= 25%`.

Idempotency: writes `state/v2-readiness.flag`. To re-arm (e.g., after V2 lands
but thresholds need re-tuning), delete the flag.

## V2 scope — what the port must deliver

1. **Real import graph over non-bash source.** Use BetterRank, or any
   equivalent tool that resolves JS/TS/Python imports into a directed graph
   (caller → callee / importer → imported).
2. **PageRank-style centrality** per file, written to
   `state/centrality.jsonl`: `{path, centrality, fan_in, fan_out}`.
3. **Merge with heat.** New aggregator `state/pruning-candidates.jsonl` joins
   `file-heat.jsonl` + `centrality.jsonl`. A candidate is
   `heat < T_heat AND centrality < T_centrality AND git_age > 60d`.
4. **Weekly surface** (Layer 3): one Telegram message with candidate rows
   `- path (heat=X, centrality=Y, Nd stale) [keep/drop]`. Decision remains
   human-gated.
5. **Keep the bash callgraph around.** Bash centrality and JS/TS centrality
   are separate dimensions — both feed the "low centrality" signal.

## Design decisions already made (do not re-litigate)

- **Primary signal is usage (heat), secondary is centrality.** Heat is ground
  truth — "is this actually running?" Centrality adds confidence. Flag on
  `low_heat AND low_centrality`, not `low_heat OR low_centrality`.
- **Decisions are human-gated.** Surface is a digest, not an auto-PR.
- **Decay half-life ~14d.** If V2 wants to tune this, see `heat-counter.sh`.

## Future-agent prompt (paste this back in when the reminder fires)

> The `scripts/v2-readiness-check.sh` reminder has fired. Implement V2 of the
> pruning signal per `workspace/docs/v2-betterrank-plan.md`.
>
> Concretely:
>
> 1. Read the current V1 artifacts: `state/file-heat.jsonl`,
>    `state/bash-callgraph.json`. Sample `traces/*.jsonl` to confirm `.paths`
>    is still populated the way `scripts/trace.sh` intends.
> 2. Pick the centrality tool. Default: BetterRank (`pip install betterrank`
>    or equivalent; confirm current name). Alternatives acceptable if they
>    produce a weighted directed import graph over JS/TS/Python.
> 3. Write `scripts/centrality.sh` (or `.py`) that outputs
>    `state/centrality.jsonl`: `{path, centrality, fan_in, fan_out}` per
>    non-bash source file. Run weekly via openclaw cron.
> 4. Write `scripts/pruning-candidates.sh` that joins heat + centrality +
>    `git log --diff-filter=A --format=%cI -- <path>` (or equivalent age
>    signal) and emits `state/pruning-candidates.jsonl`.
> 5. Write `scripts/pruning-digest.sh` — weekly Friday Telegram push with
>    rows `- path (heat=X, centrality=Y, Nd stale) [keep/drop]`. User replies
>    with drop ids; you open the PR.
> 6. Keep `scripts/bash-callgraph.sh`. Bash centrality remains a valid
>    signal for the bash half of the tree.
> 7. Delete `state/v2-readiness.flag` once V2 is shipped; re-arm thresholds
>    in `v2-readiness-check.sh` if you want a V3 gate.
>
> Guardrails:
> - Prefer extending existing scripts over new abstractions.
> - The digest is human-gated. No auto-deletes, no auto-PRs.
> - Do not mock the import graph — a wrong graph is worse than no graph.
> - Confirm with God before running the first "keep/drop" digest; thresholds
>   (`T_heat`, `T_centrality`, age) likely need one tuning pass on real data.

## Pointers

- V1 heat aggregator: `scripts/heat-counter.sh`
- V1 bash callgraph: `scripts/bash-callgraph.sh`
- Readiness trigger: `scripts/v2-readiness-check.sh`
- Path capture in traces: `scripts/trace.sh` (look for `PATHS=` block)
- Nightly wiring: `scripts/nightly.sh`
