#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -ne 1 ]; then
  echo "review-shape: usage: $0 <review.md>" >&2
  exit 2
fi

FILE="$1"
if [ ! -f "$FILE" ]; then
  echo "review-shape: missing file $FILE" >&2
  exit 2
fi

extract_section() {
  local marker="$1"
  awk -v marker="$marker" '
    $0 == marker { in_sec=1; print; next }
    in_sec && /^## / { exit }
    in_sec { print }
  ' "$FILE"
}

hyp=$(extract_section '## Hypotheses')
next=$(extract_section '## Next-step candidates')

if [ -z "$hyp" ]; then
  echo "review-shape: missing ## Hypotheses section" >&2
  exit 1
fi
if [ -z "$next" ]; then
  echo "review-shape: missing ## Next-step candidates section" >&2
  exit 1
fi

hyp_body=$(printf '%s\n' "$hyp" | tail -n +2)
next_body=$(printf '%s\n' "$next" | tail -n +2)

if printf '%s\n' "$hyp_body" | grep -qiE '_Skipped|fill in manually|_What.s the most expensive|_What pattern or gap'; then
  if ! printf '%s\n' "$hyp_body" | grep -qi 'No-op hypothesis'; then
    echo "review-shape: hypotheses still contain placeholder or skipped content" >&2
    exit 1
  fi
fi

if ! printf '%s\n' "$hyp_body" | grep -qiE '^([0-9]+\.|[-*])\s|No-op hypothesis'; then
  echo "review-shape: hypotheses need at least one concrete item or explicit no-op hypothesis" >&2
  exit 1
fi

if printf '%s\n' "$next_body" | grep -qiE '_Skipped|fill in manually|One concrete, reversible next step'; then
  if ! printf '%s\n' "$next_body" | grep -qiE 'No change selected|\- \[x\]'; then
    echo "review-shape: next-step candidates still contain placeholder or skipped content" >&2
    exit 1
  fi
fi

if ! printf '%s\n' "$next_body" | grep -qiE '^- \[[ x]\] '; then
  echo "review-shape: next-step candidates need at least one checkbox item" >&2
  exit 1
fi

printf 'ok   review-shape: %s looks complete\n' "$(basename "$FILE")"
