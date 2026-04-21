---
name: mkscript
description: Use when creating a new executable shell script. Replaces the Write+chmod pair with a single Bash call (scripts/mkscript.sh <path> <<EOF ... EOF). Flagged by daily reflect as a 6–10×/day deterministic waste.
---

# mkscript

## When to reach for this

Any time the next step would be `Write foo.sh` immediately followed by `Bash chmod +x foo.sh`.

The pair shows up in reflect as `Write:sh → Bash:chmod` (6× on 2026-04-21, 8× on 2026-04-20, and still climbing). It's pure deterministic waste — one intent, two tool calls — so it's the first pattern promoted to a helper as SEPL's Select → Improve exit.

## How to use

```
scripts/mkscript.sh <path> [mode=0755] <<'EOF'
#!/usr/bin/env bash
...body...
EOF
```

- `path` — workspace-relative or absolute. Parent dirs are `mkdir -p`'d.
- `mode` — optional, defaults to `0755`. Pass e.g. `0700` for secrets.
- Body is read from stdin. **Empty stdin is a hard error** (catches accidental redirection typos).
- One tool call. Class lands as `scripts/mkscript.sh` in traces, distinct from the `Write:sh`/`Bash:chmod` pair it replaces.

## When NOT to use

- **Editing an existing script** → use `Edit`. mkscript overwrites.
- **Non-executable file** (config, markdown, JSON) → use `Write`. mkscript always chmod's.
- **mkscript itself or its bootstrap** → circular; use Write+chmod once.

## Eval

`evals/fixtures/prefer-mkscript.json` asserts the pattern. A regression (falling back to Write+chmod) will fail the nightly run and page via `eval-notify.sh`.
