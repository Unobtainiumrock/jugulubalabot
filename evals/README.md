# evals/ — SEPL Evaluate harness

Regression harness for Tai's behavior. The nightly Reflect→Select→Improve→Evaluate→Commit loop uses this as the gate before merging a self-mutation.

## Run

```bash
bash /root/.openclaw/workspace/evals/run.sh
```

Each run creates `runs/<UTC-timestamp>/` with per-fixture `stdout.txt`, `stderr.txt`, `trace.jsonl` (trace rows inside the run's window), `meta.json`, and a top-level `summary.tsv`.

Exit 0 = all fixtures passed. Exit 1 = at least one failed.

## Benchmarks

`bench.sh` is the capability-drift lane. Unlike fixtures, benchmarks are task
dirs under `benchmarks/` with `prompt.md` plus either `test.sh` or
`expected.txt`.

```bash
bash /root/.openclaw/workspace/evals/bench.sh --list
bash /root/.openclaw/workspace/evals/bench.sh bash-loop
```

Use benchmarks for raw capability checks that should stay separate from the
policy / workflow regressions in `fixtures/`.

Benchmarks run a preflight first via `scripts/claude-print-health.sh`.
If Claude auth/network/runtime state is unhealthy, `bench.sh` fails fast with
`__preflight__` instead of spending minutes timing out each task.

When running as `root`, `bench.sh` auto-sets `IS_SANDBOX=1` if Claude's
default permission mode is `bypassPermissions`. This matches the OpenClaw VPS
runtime and avoids the root-only `--dangerously-skip-permissions` refusal seen
from plain SSH shells.

## Environment knobs

- `CLAUDE_BIN` — path to the claude CLI. Default: `claude` on PATH.
- `TIMEOUT_SECS` — per-fixture timeout. Default: 180.

## Add a fixture

Drop `fixtures/<name>.json` matching the schema in [GRADING.md](GRADING.md).

## Principles

- Each fixture runs in a **fresh** `claude -p` session — matches Telegram DM usage.
- Fixtures should be **read-only** — no workspace side effects.
- **Grow from real failures.** When Tai screws up, add the fixture with the *correct* behavior.
