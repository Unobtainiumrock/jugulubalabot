#!/usr/bin/env bash
# Data-conditioned reminder: fires a Telegram nudge when the codebase has
# outgrown the Layer-2 bash-callgraph stand-in and is ready for the
# BetterRank (real PageRank on JS/TS/Python import graph) port.
#
# Trigger conditions (any one is sufficient):
#   (a) >= 25 source files under scripts/** with extension .py|.ts|.tsx|.js|.jsx
#   (b) >= 100 tracked files in state/file-heat.jsonl AND non-bash fraction
#       of those tracked files >= 25%
#
# Idempotent: once fired, drops state/v2-readiness.flag and stays silent.
# Remove that flag if you want to re-arm (e.g., after completing V2).
set -euo pipefail

WORKSPACE="${WORKSPACE:-/root/.openclaw/workspace}"
STATE_DIR="$WORKSPACE/state"
FLAG="$STATE_DIR/v2-readiness.flag"
HEAT_FILE="$STATE_DIR/file-heat.jsonl"
SPEC_PATH="docs/v2-betterrank-plan.md"
OPENCLAW="${OPENCLAW:-/usr/bin/openclaw}"
CHAT_TARGET="${V2_NOTIFY_TARGET:-8692339838}"
CHANNEL="${V2_NOTIFY_CHANNEL:-telegram}"

mkdir -p "$STATE_DIR"

if [ -f "$FLAG" ]; then
  exit 0
fi

# (a) Count non-bash source files in the tree.
NONBASH_TREE=$(find "$WORKSPACE" \
  -path "$WORKSPACE/.git" -prune -o \
  -path "$WORKSPACE/evals/runs" -prune -o \
  -path "$WORKSPACE/traces" -prune -o \
  -path "$WORKSPACE/memory" -prune -o \
  -type f \( -name '*.py' -o -name '*.ts' -o -name '*.tsx' -o -name '*.js' -o -name '*.jsx' \) \
  -print 2>/dev/null | wc -l)

# (b) Tracked-file metrics from heat file.
if [ -f "$HEAT_FILE" ] && [ -s "$HEAT_FILE" ]; then
  TRACKED_TOTAL=$(wc -l < "$HEAT_FILE")
  TRACKED_NONBASH=$(jq -r 'select(.path | test("\\.(py|ts|tsx|js|jsx)$")) | .path' "$HEAT_FILE" | wc -l)
else
  TRACKED_TOTAL=0
  TRACKED_NONBASH=0
fi

REASON=""
if [ "$NONBASH_TREE" -ge 25 ]; then
  REASON="non-bash source files in tree: $NONBASH_TREE (>= 25)"
elif [ "$TRACKED_TOTAL" -ge 100 ]; then
  # fraction = nonbash/total, check >= 25% via integer math: 4*nonbash >= total
  if [ $(( 4 * TRACKED_NONBASH )) -ge "$TRACKED_TOTAL" ]; then
    REASON="tracked files: $TRACKED_TOTAL (>=100), non-bash: $TRACKED_NONBASH (>=25%)"
  fi
fi

if [ -z "$REASON" ]; then
  exit 0
fi

MSG="V2 pruning-signal readiness trigger fired

$REASON

Layer 2 v1 (grep callgraph) has served its purpose — time to port the
centrality signal to a real PageRank (BetterRank) over the JS/TS/Python
import graph.

Spec + next-step prompt: workspace/$SPEC_PATH

When ready: delete state/v2-readiness.flag to re-arm."

"$OPENCLAW" message send --channel "$CHANNEL" --target "$CHAT_TARGET" \
  --message "$MSG" < /dev/null || true

printf '{"fired":"%s","reason":"%s"}\n' "$(date -u +%FT%TZ)" "$REASON" > "$FLAG"
echo "v2-readiness: fired ($REASON)" >&2
