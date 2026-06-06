#!/usr/bin/env bash
# UserPromptSubmit hook for mechanical infra-recovery prompts.
# Pushes the answer toward a concrete next-steps sequence instead of
# bouncing the choice back to the user.

set -uo pipefail
trap 'echo "{}"; exit 0' ERR

INPUT=$(cat)
PROMPT=$(jq -r '.prompt // ""' <<< "$INPUT" 2>/dev/null)
[ -z "$PROMPT" ] && { echo "{}"; exit 0; }

PROMPT_LC=$(printf '%s' "${PROMPT:0:2000}" | tr '[:upper:]' '[:lower:]')

case "$PROMPT_LC" in
  *"permission denied (publickey)"*"next 3 concrete actions"* )
    ;;
  *)
    echo "{}"
    exit 0
    ;;
esac

MSG=$(cat <<'EOF'
INFRA-LOOP reflex.

This is a mechanical recovery prompt, not a menu prompt. Reply with 3 concrete actions in order that continue the work without asking the user to choose a path first.

Required content:
- action 1 diagnoses the current auth path (`git remote -v`, existing SSH keys, `gh auth status` or equivalent)
- action 2 creates or installs the missing credential path (`ssh-keygen`, HTTPS+PAT, or tool install) as an execution step, not an option list
- action 3 retries the push or prepares the exact external dependency that remains

Required closing shape: the FINAL line of your reply commits to execution — e.g., "Starting action 1 now.", "Executing the sequence.", or the actual tool call. The final line MUST NOT be a question and MUST NOT ask the user to confirm, pick, or green-light the next step. A trailing "Want me to execute action 1 now?" / "Should I run X?" / "Let me know if you want me to proceed" is the same failure mode as a menu — it bounces the mechanical sub-step back to the user. The only legitimate gate is a real external dependency you cannot satisfy yourself (e.g., the user adding the public key to their own GitHub account); name that gate inline and keep going on every step that is not gated.

Forbidden shape (any of these = fail):
- "which option do you prefer", "how would you like me to proceed", "before I continue"
- "want me to", "should I", "shall I", "do you want me to", "let me know if you want", "ready when you are"
- any response that presents paths without committing to the next action sequence, or any trailing question that defers a mechanical sub-step to the user
EOF
)

jq -n --arg msg "$MSG" '{"hookSpecificOutput":{"hookEventName":"UserPromptSubmit","additionalContext":$msg}}'
