#!/usr/bin/env bash
# bin-autoheal.sh — close the trace classifier's known gaps.
# When new tools appear in the harness (Monitor, TaskOutput, …) and trace.sh's
# inline classifier doesn't know them, they land as bin="other". This script
# scans a day's trace, infers a bin from the tool name where confident, and
# appends the mapping to state/bin-overrides.jsonl, which trace.sh consults
# whenever its classifier returns "other".
#
# Exit 0 = nothing to heal, or every gap was inferred (notify "self-healed").
# Exit 1 = some tools couldn't be inferred (notify human with the names).
#
# Usage:
#   bash scripts/bin-autoheal.sh             # today
#   bash scripts/bin-autoheal.sh 2026-04-30  # specific date

set -uo pipefail

WORKSPACE="/root/.openclaw/workspace"
DATE="${1:-$(date -u +%F)}"
TRACE="$WORKSPACE/traces/$DATE.jsonl"
OVERRIDES="$WORKSPACE/state/bin-overrides.jsonl"
mkdir -p "$WORKSPACE/state"
touch "$OVERRIDES"

if [ ! -f "$TRACE" ]; then
  echo "bin-autoheal: no trace file for $DATE — nothing to do"
  exit 0
fi

mapfile -t unknowns < <(jq -r 'select(.bin == "other") | .tool' "$TRACE" 2>/dev/null | sort -u | grep -v '^$' || true)
if [ "${#unknowns[@]}" -eq 0 ]; then
  echo "bin-autoheal: no 'other' rows for $DATE"
  exit 0
fi

# Name-based inference. New patterns are added here as they appear; truly
# novel tools fall through to the unhealed list and surface to the human.
infer_bin() {
  case "$1" in
    Monitor|TaskOutput)                                  echo "file_ground" ;;
    TaskStop|PushNotification|AskUserQuestion)           echo "comms" ;;
    CronCreate|CronDelete|CronList|RemoteTrigger)        echo "scheduling" ;;
    EnterPlanMode|ExitPlanMode|EnterWorktree|ExitWorktree) echo "exec" ;;
    NotebookEdit)                                        echo "self_modify" ;;
    WebFetch|WebSearch)                                  echo "external_fetch" ;;
    *)                                                   echo "" ;;
  esac
}

healed=0
healed_lines=()
unhealed=()
for t in "${unknowns[@]}"; do
  if grep -qF "\"tool\":\"$t\"" "$OVERRIDES" 2>/dev/null; then
    continue   # already in the overrides file; trace.sh will pick it up
  fi
  inferred=$(infer_bin "$t")
  if [ -z "$inferred" ]; then
    unhealed+=("$t")
    continue
  fi
  jq -cn --arg t "$t" --arg b "$inferred" --arg d "$(date -u +%F)" \
    '{tool: $t, bin: $b, added: $d, by: "auto-heal"}' >> "$OVERRIDES"
  healed_lines+=("$t -> $inferred")
  healed=$((healed + 1))
done

# Print a stable, parseable summary the caller (nightly.sh) can extract.
if [ "$healed" -gt 0 ]; then
  for line in "${healed_lines[@]}"; do echo "HEALED: $line"; done
fi
if [ "${#unhealed[@]}" -gt 0 ]; then
  echo "UNHEALED: ${unhealed[*]}"
  exit 1
fi

echo "DONE: healed=$healed"
exit 0
