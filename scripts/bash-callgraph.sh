#!/usr/bin/env bash
# Layer 2 v1 of the pruning signal: structural call graph for bash scripts.
# Greps every *.sh under scripts/ for references to other scripts and writes
# state/bash-callgraph.json. Cheap first-pass stand-in for BetterRank (which
# needs a real import graph); see docs/v2-betterrank-plan.md for the upgrade.
set -euo pipefail

WORKSPACE="${WORKSPACE:-/root/.openclaw/workspace}"
STATE_DIR="$WORKSPACE/state"
SCRIPTS_DIR="$WORKSPACE/scripts"
OUT="$STATE_DIR/bash-callgraph.json"

mkdir -p "$STATE_DIR"

TMP=$(mktemp)
trap 'rm -f "$TMP"' EXIT

# Emit caller,callee pairs. A callee is any "scripts/<name>.sh" substring
# appearing in a shell file other than the file itself.
while IFS= read -r -d '' f; do
  caller="scripts/$(basename "$f")"
  # Pull unique referenced scripts; exclude self-refs.
  grep -oE 'scripts/[A-Za-z0-9_.-]+\.sh' "$f" 2>/dev/null \
    | sort -u \
    | awk -v c="$caller" '$0 != c { printf "%s\t%s\n", c, $0 }' \
    >> "$TMP" || true
done < <(find "$SCRIPTS_DIR" -maxdepth 1 -type f -name '*.sh' -print0)

# Build JSON: edges + per-node fan_in / fan_out.
jq -R -s -c --arg gen "$(date -u +%FT%TZ)" '
  split("\n") | map(select(length > 0))
  | map(split("\t") | {from: .[0], to: .[1]}) as $edges
  | ( $edges | group_by(.from) | map({(.[0].from): (length)}) | add // {} ) as $fan_out
  | ( $edges | group_by(.to)   | map({(.[0].to):   (length)}) | add // {} ) as $fan_in
  | ( ($fan_out | keys) + ($fan_in | keys) | unique ) as $nodes
  | {
      generated: $gen,
      edges: $edges,
      nodes: ($nodes | map({(.): {fan_in: ($fan_in[.] // 0), fan_out: ($fan_out[.] // 0)}}) | add // {})
    }
' "$TMP" > "$OUT"

EDGES=$(jq -r '.edges | length' "$OUT")
NODES=$(jq -r '.nodes | length' "$OUT")
echo "bash-callgraph: $NODES nodes, $EDGES edges" >&2
