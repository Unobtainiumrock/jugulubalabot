#!/usr/bin/env bash
# backlog-triage — wraps backlog-reconcile and adds a trace-activity
# cross-reference. Read-only on backlog.jsonl. Human-gated: never closes
# items, never passes --apply downstream.
#
# Usage:
#   scripts/backlog-triage.sh              # default 14-day trace window
#   scripts/backlog-triage.sh --days 30    # widen window
#
# Output sections (all markdown, exit 0 always):
#   ## Resolved-but-open (from reconcile)
#   ## Active in traces
#   ## Stale (no activity, old)
#   ## Stalled (doing, idle)
#
# Trace cross-reference rule:
#   For each open/doing backlog id (6-char hex), grep traces/*.jsonl in the
#   window and check whether the id appears anywhere in the line (covers
#   input_hash and class fields). Most recent matching ts gives "last
#   activity"; created date and status drive the stale/stalled buckets.

set -uo pipefail

WORKSPACE="/root/.openclaw/workspace"
BACKLOG="$WORKSPACE/backlog.jsonl"
TRACES_DIR="$WORKSPACE/traces"

DAYS=14
while [ $# -gt 0 ]; do
  case "$1" in
    --days)
      DAYS="${2:-14}"
      shift 2 || break
      ;;
    *)
      echo "unknown arg: $1" >&2
      exit 2
      ;;
  esac
done

if [ ! -s "$BACKLOG" ]; then
  echo "backlog-triage: no backlog file at $BACKLOG" >&2
  echo "## Resolved-but-open (from reconcile)"
  echo ""
  echo "_no backlog file_"
  exit 0
fi

# --- Section 1: reconcile ---------------------------------------------------
echo "## Resolved-but-open (from reconcile)"
echo ""
RECONCILE_OUT=$(bash "$WORKSPACE/scripts/backlog-reconcile.sh" 2>&1)
RECONCILE_RC=$?
if [ -z "$RECONCILE_OUT" ]; then
  echo "_(no output)_"
else
  printf '```\n%s\n```\n' "$RECONCILE_OUT"
fi
echo ""
# rc=1 from reconcile just means "matches found, run --apply"; not an error here.

# --- Gather open IDs --------------------------------------------------------
# Build TSV: id<TAB>status<TAB>ts_created
OPEN_TSV=$(jq -r '
  select(.status == "open" or .status == "doing")
  | [.id, .status, .ts_created, .title] | @tsv' "$BACKLOG" 2>/dev/null)

if [ -z "$OPEN_TSV" ]; then
  echo "## Active in traces"
  echo ""
  echo "_no open or doing backlog items — nothing to cross-reference_"
  echo ""
  echo "## Stale (no activity, old)"
  echo ""
  echo "_no open or doing backlog items_"
  echo ""
  echo "## Stalled (doing, idle)"
  echo ""
  echo "_no doing backlog items_"
  echo ""
  echo "backlog-triage: no open/doing items; nothing to cross-reference" >&2
  exit 0
fi

# --- Resolve trace window ---------------------------------------------------
# List trace files within window. Use mtime as a proxy for trace date — the
# files are named YYYY-MM-DD.jsonl and rotated daily, so mtime is fine.
TRACE_FILES=""
if [ -d "$TRACES_DIR" ]; then
  TRACE_FILES=$(find "$TRACES_DIR" -maxdepth 1 -name '*.jsonl' -mtime -"$DAYS" 2>/dev/null | sort)
fi

NOW_EPOCH=$(date -u +%s)
SEVEN_D_AGO=$(( NOW_EPOCH - 7*86400 ))
WINDOW_AGO=$(( NOW_EPOCH - DAYS*86400 ))

# Helpers --------------------------------------------------------------------
iso_to_epoch() {
  # Best-effort ISO-8601 → epoch. Returns 0 on parse failure.
  local s="$1"
  [ -z "$s" ] && { echo 0; return; }
  date -u -d "$s" +%s 2>/dev/null || echo 0
}

# Find the most recent trace ts that mentions an id within the window.
# Echoes ISO timestamp or empty string.
last_trace_mention() {
  local id="$1"
  [ -z "$TRACE_FILES" ] && { echo ""; return; }
  # grep across files in newest-last order; take the last match's ts.
  # Files sort lexicographically which equals chronologically here.
  local last=""
  local f line ts
  for f in $TRACE_FILES; do
    # tail-grep keeps memory small even on big trace files.
    line=$(grep -F "$id" "$f" 2>/dev/null | tail -n 1)
    if [ -n "$line" ]; then
      ts=$(printf '%s' "$line" | jq -r '.ts // empty' 2>/dev/null)
      [ -n "$ts" ] && last="$ts"
    fi
  done
  echo "$last"
}

# --- Cross-reference --------------------------------------------------------
ACTIVE_LINES=""
STALE_LINES=""
STALLED_LINES=""

while IFS=$'\t' read -r id status ts_created title; do
  [ -z "$id" ] && continue
  last_ts=$(last_trace_mention "$id")
  created_epoch=$(iso_to_epoch "$ts_created")
  if [ -n "$last_ts" ]; then
    # Active in traces.
    last_date="${last_ts%%T*}"
    ACTIVE_LINES+="- \`$id\` [$status] $title — last activity: $last_date"$'\n'
    # Stalled-doing check: doing + last mention older than 7d.
    if [ "$status" = "doing" ]; then
      last_epoch=$(iso_to_epoch "$last_ts")
      if [ "$last_epoch" -gt 0 ] && [ "$last_epoch" -lt "$SEVEN_D_AGO" ]; then
        STALLED_LINES+="- \`$id\` doing, last trace activity $last_date (>7d ago) — $title"$'\n'
      fi
    fi
  else
    # No trace mention. Stale if created >14d ago.
    if [ "$created_epoch" -gt 0 ] && [ "$created_epoch" -lt "$WINDOW_AGO" ]; then
      created_date="${ts_created%%T*}"
      STALE_LINES+="- \`$id\` [$status] $title — created $created_date, no trace activity in last ${DAYS}d"$'\n'
    fi
  fi
done <<< "$OPEN_TSV"

# --- Emit sections ----------------------------------------------------------
echo "## Active in traces"
echo ""
if [ -n "$ACTIVE_LINES" ]; then
  printf '%s' "$ACTIVE_LINES"
else
  echo "_no open/doing items showed up in the last ${DAYS}d of traces_"
fi
echo ""

echo "## Stale (no activity, old)"
echo ""
if [ -n "$STALE_LINES" ]; then
  printf '%s' "$STALE_LINES"
else
  echo "_no stale items (open >14d with zero trace activity)_"
fi
echo ""

echo "## Stalled (doing, idle)"
echo ""
if [ -n "$STALLED_LINES" ]; then
  printf '%s' "$STALLED_LINES"
else
  echo "_no stalled doing items (last activity within 7d)_"
fi
echo ""

n_active=$(printf '%s' "$ACTIVE_LINES" | grep -c '^-' || true)
n_stale=$(printf '%s' "$STALE_LINES" | grep -c '^-' || true)
n_stalled=$(printf '%s' "$STALLED_LINES" | grep -c '^-' || true)
echo "backlog-triage: window=${DAYS}d active=$n_active stale=$n_stale stalled=$n_stalled" >&2

exit 0
