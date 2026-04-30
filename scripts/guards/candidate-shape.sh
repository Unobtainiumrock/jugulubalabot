#!/usr/bin/env bash
# candidate-shape.sh — refuses Improve candidates that are observation, not
# improvement. Caught a tautology on 2026-04-30 when bootstrap emitted
# "Re-run the failing fixture set..." and Track 4 burned its cycle on it.
#
# Usage:
#   candidate-shape.sh "<candidate body line>"
#   echo "<body>" | candidate-shape.sh
#
# Exit:
#   0 = implementable (passes all shape checks)
#   1 = refused (matches an observation/tautology pattern)
#   2 = empty/missing input
set -euo pipefail

body="${1:-}"
if [ -z "$body" ] && [ ! -t 0 ]; then
  body=$(cat)
fi
if [ -z "$body" ]; then
  echo "candidate-shape: empty input" >&2
  exit 2
fi

trimmed=$(printf '%s' "$body" | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')
lc=$(printf '%s' "$trimmed" | tr '[:upper:]' '[:lower:]')

fail() {
  printf 'candidate-shape: REFUSED — %s\n' "$1" >&2
  printf 'candidate-shape: body: %s\n' "$trimmed" >&2
  exit 1
}

if printf '%s' "$lc" | grep -qE '^(re-?run|run again|run the|run all)\b'; then
  fail "candidate starts with re-run/run — observation, not improvement"
fi

if printf '%s' "$lc" | grep -qE '^(audit|inspect|measure|count|check|read|report|look at|review)\b'; then
  fail "candidate starts with an observation verb (audit/inspect/measure/count/check/read/report/look-at/review)"
fi

if printf '%s' "$lc" | grep -qE '^if .*\b(run|re-?run|invoke|trigger)\b'; then
  fail "candidate is a conditional pipeline instruction — orchestration belongs in cron"
fi

if printf '%s' "$lc" | grep -qE '^(run|invoke|trigger|fire|kick off) (scripts?/|the )'; then
  fail "candidate is a script-invocation, not a code change"
fi

if ! printf '%s' "$lc" | grep -qE '(scripts?/|hooks?/|evals/|fixtures?/|\.md|\.sh|\.json|fixture|hook|guard|rule|template|alert|cron|memory|soul\.md|agents\.md|backlog)'; then
  fail "candidate names no concrete deliverable (no file path / fixture / hook / rule)"
fi

printf 'ok   candidate-shape: looks implementable\n'
exit 0
