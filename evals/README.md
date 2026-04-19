# evals/ — SEPL Evaluate harness

Regression harness for Tai's behavior. The nightly Reflect→Select→Improve→Evaluate→Commit loop uses this as the gate before merging a self-mutation.

## Run

```bash
bash /root/.openclaw/workspace/evals/run.sh
```

Each run creates `runs/<UTC-timestamp>/` with per-fixture `stdout.txt`, `stderr.txt`, `trace.jsonl` (trace rows inside the run's window), `meta.json`, and a top-level `summary.tsv`.

Exit 0 = all fixtures passed. Exit 1 = at least one failed.

## Environment knobs

- `CLAUDE_BIN` — path to the claude CLI. Default: `claude` on PATH.
- `TIMEOUT_SECS` — per-fixture timeout. Default: 180.

## Add a fixture

Drop `fixtures/<name>.json` matching the schema in [GRADING.md](GRADING.md).

## Principles

- Each fixture runs in a **fresh** `claude -p` session — matches Telegram DM usage.
- Fixtures should be **read-only** — no workspace side effects.
- **Grow from real failures.** When Tai screws up, add the fixture with the *correct* behavior.
