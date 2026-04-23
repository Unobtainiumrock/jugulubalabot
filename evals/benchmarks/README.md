# Benchmarks

Benchmarks are for raw capability drift, not policy compliance.

Each task lives under `evals/benchmarks/<task>/` and must include:

- `prompt.md`
- `test.sh` or `expected.txt`

Run with:

```bash
bash evals/bench.sh --list
bash evals/bench.sh bash-loop
```

Artifacts land under `evals/bench-runs/<UTC>/`.
