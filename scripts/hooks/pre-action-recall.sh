#!/usr/bin/env bash
# pre-action-recall — PreToolUse hook that surfaces relevant prior
# mistakes / feedback memories before the model commits to an action.
# Non-blocking by design: emits additionalContext only.
#
# This closes the discipline-only failure mode where the rule existed
# but the reflex didn't fire. Pre-bash-guard intercepts known-bad
# command shapes; this hook intercepts intent — semantic patterns the
# regex guard can't catch.
#
# Index: state/recall-index.tsv (refreshed by build-recall-index.sh)
# Format: <pattern>\t<kind>\t<source>\t<rule>
#
# Per-session dedup: state/recall-fired.txt (lines = fired pattern hashes
# for this session). Each pattern fires at most once per session to avoid
# repetitive nagging.
#
# Kill switches:
#   - state/.recall-off            session-wide bypass (skips everything)
#   - state/.recall-enforce-off    skips the deny step only; surface still fires
#   - OPENCLAW_RECALL_OFF=1 <cmd>  per-call bypass (Bash only, full skip)
#   - OPENCLAW_RECALL_ENFORCE_OFF=1 <cmd>  per-call bypass of deny step only
#
# Deny allowlist (escalates from additionalContext to permissionDecision:"deny"):
#   - workspace_commit_no_ask: tool=Bash AND command~"^git commit" AND
#     cwd inside workspace. Source: feedback_no_ask_workspace_commits.
#     Forces the rule into the model's hands instead of relying on it
#     reading the surface message.
#
# Budget: <50ms target. Always exit 0.

set -uo pipefail
WORKSPACE="/root/.openclaw/workspace"
INDEX="$WORKSPACE/state/recall-index.tsv"
FIRED="$WORKSPACE/state/recall-fired.txt"
LOG="$WORKSPACE/state/recall-log.jsonl"

# Fail-safe: any error path -> emit empty + exit 0 (silent allow).
trap 'echo "{}"; exit 0' ERR

# Session bypass (full)
[ -f "$WORKSPACE/state/.recall-off" ] && { echo "{}"; exit 0; }

INPUT=$(cat)
TOOL=$(jq -r '.tool_name // ""' <<< "$INPUT" 2>/dev/null)
[ -z "$TOOL" ] && { echo "{}"; exit 0; }
CWD=$(jq -r '.cwd // ""' <<< "$INPUT" 2>/dev/null)

# ---- DENY allowlist (runs before surface walk) -------------------------
# Skipped entirely if state/.recall-enforce-off exists.
if [ ! -f "$WORKSPACE/state/.recall-enforce-off" ]; then
  # Rule: workspace_commit_no_ask
  if [ "$TOOL" = "Bash" ]; then
    CMD=$(jq -r '.tool_input.command // ""' <<< "$INPUT" 2>/dev/null)
    if [[ "$CMD" != *"OPENCLAW_RECALL_ENFORCE_OFF=1"* ]] \
       && [[ "$CMD" != *"OPENCLAW_RECALL_OFF=1"* ]]; then
      case "$CWD" in
        "$WORKSPACE"|"$WORKSPACE"/*)
          if [[ "$CMD" =~ ^[[:space:]]*git[[:space:]]+commit([[:space:]]|$) ]]; then
            REASON="workspace_commit_no_ask — workspace commits are pre-approved (feedback_no_ask_workspace_commits). If you asked the user before this commit, that IS the regression: the recall surfaced the rule and you gated anyway. To proceed, prefix the command with OPENCLAW_RECALL_ENFORCE_OFF=1 (per-call) or touch state/.recall-enforce-off (session-wide). The override prefix is the proof you read this message."
            TS=$(date -u +%Y-%m-%dT%H:%M:%S.%3NZ)
            printf '{"ts":"%s","tool":"Bash","kind":"deny","source":"workspace_commit_no_ask","rule":%s}\n' \
              "$TS" "$(jq -Rc . <<< "$REASON")" >> "$LOG" 2>/dev/null || true
            jq -n --arg r "$REASON" '{"hookSpecificOutput": {"hookEventName": "PreToolUse", "permissionDecision": "deny", "permissionDecisionReason": $r}}'
            exit 0
          fi
          ;;
      esac
    fi
  fi
fi

# Index missing or empty -> nothing to recall (surface phase)
[ ! -s "$INDEX" ] && { echo "{}"; exit 0; }

# Skip read-only / low-risk tools to reduce noise
case "$TOOL" in
  Read|Glob|Grep|TodoWrite|ToolSearch|NotebookRead) echo "{}"; exit 0 ;;
esac

# Extract searchable haystack from tool input. Per-tool rules:
#   Bash       -> command field
#   Edit       -> file_path + new_string (first 500 chars)
#   Write      -> file_path + content   (first 500 chars)
#   Skill      -> skill name + args
#   WebFetch   -> url
#   Agent/Task -> description + prompt (first 500 chars)
#   default    -> JSON-stringified tool_input (first 500 chars)
HAYSTACK=$(jq -r --arg t "$TOOL" '
  .tool_input as $i |
  if $t == "Bash" then
    ($i.command // "")
  elif $t == "Edit" then
    (($i.file_path // "") + " " + (($i.new_string // "") | tostring)[:500])
  elif $t == "Write" then
    (($i.file_path // "") + " " + (($i.content // "") | tostring)[:500])
  elif $t == "Skill" then
    (($i.skill // "") + " " + ($i.args // ""))
  elif $t == "WebFetch" then
    ($i.url // "")
  elif $t == "Agent" or $t == "Task" then
    (($i.description // "") + " " + (($i.prompt // "") | tostring)[:500])
  else
    ($i | tostring)[:500]
  end
' <<< "$INPUT" 2>/dev/null)

[ -z "$HAYSTACK" ] && { echo "{}"; exit 0; }

# Per-call bypass for Bash (string check; cheap)
if [ "$TOOL" = "Bash" ] && [[ "$HAYSTACK" == *"OPENCLAW_RECALL_OFF=1"* ]]; then
  echo "{}"; exit 0
fi

# Lowercase haystack for case-insensitive substring match
HAY_LC=$(printf '%s' "$HAYSTACK" | tr '[:upper:]' '[:lower:]')

# Walk the index; collect at most 2 distinct hits not yet fired this session
mkdir -p "$(dirname "$FIRED")" 2>/dev/null
touch "$FIRED" 2>/dev/null
HITS_FILE=$(mktemp 2>/dev/null) || { echo "{}"; exit 0; }
HIT_COUNT=0

while IFS=$'\t' read -r pattern kind source rule; do
  [ -z "$pattern" ] && continue
  PAT_LC=$(printf '%s' "$pattern" | tr '[:upper:]' '[:lower:]')
  case "$HAY_LC" in
    *"$PAT_LC"*)
      # Hash the pattern for per-session dedup
      HASH=$(printf '%s' "$pattern" | md5sum | cut -c1-16)
      if grep -qF "$HASH" "$FIRED" 2>/dev/null; then
        continue
      fi
      printf '%s\t%s\t%s\t%s\n' "$kind" "$source" "$rule" "$HASH" >> "$HITS_FILE"
      HIT_COUNT=$((HIT_COUNT + 1))
      [ "$HIT_COUNT" -ge 2 ] && break
      ;;
  esac
done < "$INDEX"

if [ "$HIT_COUNT" -eq 0 ]; then
  rm -f "$HITS_FILE"
  echo "{}"; exit 0
fi

# Build the additionalContext message and record fired hashes
TS=$(date -u +%Y-%m-%dT%H:%M:%S.%3NZ)
MSG="RECALL — prior signal matches this action:"
while IFS=$'\t' read -r kind source rule hash; do
  MSG=$(printf '%s\n  · [%s] %s — %s' "$MSG" "$kind" "$source" "$rule")
  echo "$hash" >> "$FIRED" 2>/dev/null
  # Audit log
  printf '{"ts":"%s","tool":%s,"kind":%s,"source":%s,"rule":%s}\n' \
    "$TS" \
    "$(jq -Rc . <<< "$TOOL")" \
    "$(jq -Rc . <<< "$kind")" \
    "$(jq -Rc . <<< "$source")" \
    "$(jq -Rc . <<< "$rule")" \
    >> "$LOG" 2>/dev/null || true
done < "$HITS_FILE"
rm -f "$HITS_FILE"

# Emit non-blocking additionalContext via PreToolUse hookSpecificOutput
jq -n --arg msg "$MSG" '{"hookSpecificOutput": {"hookEventName": "PreToolUse", "additionalContext": $msg}}'
exit 0
