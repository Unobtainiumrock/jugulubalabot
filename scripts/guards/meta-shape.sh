#!/usr/bin/env bash
# Artifact-shape check: every fixture's meta.json must have the required
# keys with non-null values. Generalizes past the specific .graders=null
# regression (96284c) to any shape drift.
#
# Usage: scripts/guards/meta-shape.sh <run_dir>
#   run_dir: directory containing one subdir per fixture, each with meta.json
#
# Exit: 0 = all meta.json files shape-valid; 1 = at least one invalid.
set -uo pipefail

RUN_DIR="${1:-}"
if [ -z "$RUN_DIR" ] || [ ! -d "$RUN_DIR" ]; then
  echo "meta-shape: usage: $0 <run_dir>" >&2
  exit 2
fi

# start/end = ISO timestamps (string, non-empty)
# exit      = integer
# result    = "PASS" or "FAIL"
# notes     = string (may be empty "")
# graders   = array (may be empty [])
REQUIRED_STR=(start end result)
REQUIRED_NUM=(exit)
REQUIRED_ARR=(graders)

fail=0
checked=0
while IFS= read -r -d '' meta; do
  checked=$((checked+1))
  fx=$(basename "$(dirname "$meta")")
  for k in "${REQUIRED_STR[@]}"; do
    v=$(jq -r ".$k // \"\"" "$meta" 2>/dev/null)
    if [ -z "$v" ] || [ "$v" = "null" ]; then
      echo "FAIL $fx: .$k is null/empty"
      fail=1
    fi
  done
  for k in "${REQUIRED_NUM[@]}"; do
    v=$(jq -r "if (.$k | type) == \"number\" then \"ok\" else \"bad\" end" "$meta" 2>/dev/null)
    if [ "$v" != "ok" ]; then
      echo "FAIL $fx: .$k is not a number"
      fail=1
    fi
  done
  for k in "${REQUIRED_ARR[@]}"; do
    v=$(jq -r "if (.$k | type) == \"array\" then \"ok\" else \"bad\" end" "$meta" 2>/dev/null)
    if [ "$v" != "ok" ]; then
      echo "FAIL $fx: .$k is not an array"
      fail=1
    fi
  done
  notes_type=$(jq -r "if (.notes | type) == \"string\" then \"ok\" else \"bad\" end" "$meta" 2>/dev/null)
  if [ "$notes_type" != "ok" ]; then
    echo "FAIL $fx: .notes is not a string"
    fail=1
  fi
done < <(find "$RUN_DIR" -mindepth 2 -maxdepth 2 -name 'meta.json' -print0)

if [ "$checked" -eq 0 ]; then
  echo "meta-shape: no meta.json files found under $RUN_DIR" >&2
  exit 2
fi

if [ "$fail" -eq 0 ]; then
  printf 'ok   meta-shape: %s fixture meta.json(s) valid\n' "$checked"
fi
exit "$fail"
