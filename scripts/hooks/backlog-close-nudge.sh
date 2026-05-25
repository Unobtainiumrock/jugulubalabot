#!/usr/bin/env bash
# UserPromptSubmit hook: when God names "backlog item <id>" adjacent to a
# ship/fix/resolve verb, inject the exact close-step line so the model has
# the literal string to copy verbatim into sentence 1.
#
# Tight by design — wording-only SOUL edits failed three times; the prior
# wide-net hook (2026-05-24) regressed review-shape fixtures. Trigger only
# on the literal "backlog item <id>" phrase and only when a ship verb sits
# in the same prompt. Skip outright if the prompt is about reviews/reflect
# stubs.

set -uo pipefail
trap 'echo "{}"; exit 0' ERR

INPUT=$(cat)
PROMPT=$(jq -r '.prompt // ""' <<< "$INPUT" 2>/dev/null)
[ -z "$PROMPT" ] && { echo "{}"; exit 0; }

PROMPT_LC=$(printf '%s' "${PROMPT:0:2000}" | tr '[:upper:]' '[:lower:]')

case "$PROMPT_LC" in
  *"review stub"*|*"reflect review"*|*"review sidecar"*|*"hypotheses"*)
    echo "{}"; exit 0 ;;
esac

ID=""
if [[ "$PROMPT_LC" =~ backlog[[:space:]]+item[[:space:]]+([a-z0-9]{4,}) ]]; then
  ID="${BASH_REMATCH[1]}"
elif [[ "$PROMPT_LC" =~ resolved[[:space:]]+backlog[[:space:]]+([a-z0-9]{4,}) ]]; then
  ID="${BASH_REMATCH[1]}"
fi
[ -z "$ID" ] && { echo "{}"; exit 0; }

HAS_SHIP=0
for verb in "shipping" "shipped" "ship the" "resolved" "fixed" "closed" "landed"; do
  case "$PROMPT_LC" in
    *"$verb"*) HAS_SHIP=1; break ;;
  esac
done
[ "$HAS_SHIP" -eq 0 ] && { echo "{}"; exit 0; }

MSG=$(cat <<INNER
BACKLOG-CLOSE reflex.

God named backlog ID '$ID' next to a ship/fix/resolve verb. Sentence 1 of
your reply MUST be this exact line, copied verbatim:

\`scripts/backlog.sh done $ID\`

The script is idempotent on \`done\`: missing IDs no-op and exit 0, so the
close line is safe even if commit hash, path, or ID-in-registry look off.
That removes the only honest reason to skip it. Premise checks go in
paragraph 2 — never in place of sentence 1. Opening with "premise doesn't
check out" or "$ID isn't in backlog.jsonl" is the documented failure shape.

Self-check: does your first sentence contain the literal string
\`scripts/backlog.sh done $ID\`? If no, rewrite.
INNER
)

jq -n --arg msg "$MSG" '{"hookSpecificOutput":{"hookEventName":"UserPromptSubmit","additionalContext":$msg}}'
