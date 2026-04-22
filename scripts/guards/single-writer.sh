#!/usr/bin/env bash
# Single-writer lint. Each rule pins a file whose write-path must have
# exactly one textual emitter in a specific script. Catches the class of
# bug where meta.json was written early AND late, and the late write
# silently dropped fields (96284c, 2026-04-19 → 2026-04-22).
#
# Add a rule: append to RULES as "label|file_to_scan|regex|expected_count".
#
# Exit: 0 = all rules pass; 1 = at least one rule violated.
set -uo pipefail

WORKSPACE="${OPENCLAW_WORKSPACE:-/root/.openclaw/workspace}"
cd "$WORKSPACE"

RULES=(
  'evals/run.sh meta.json|evals/run.sh|> "\$fx_dir/meta\.json"|1'
)

fail=0
for rule in "${RULES[@]}"; do
  IFS='|' read -r label file regex expected <<< "$rule"
  if [ ! -f "$file" ]; then
    printf 'SKIP %s — file missing: %s\n' "$label" "$file"
    continue
  fi
  actual=$(grep -cE "$regex" "$file" || true)
  if [ "$actual" != "$expected" ]; then
    printf 'FAIL %s — expected %s writer(s) matching /%s/ in %s, found %s\n' \
      "$label" "$expected" "$regex" "$file" "$actual"
    fail=1
  else
    printf 'ok   %s (%s writer in %s)\n' "$label" "$actual" "$file"
  fi
done

exit "$fail"
