#!/usr/bin/env bash
# memory-curator — surface high-value daily-log fragments as candidates for
# promotion into MEMORY.md. Read-only: prints to stdout, never writes.
#
# Usage:
#   bash scripts/memory-curator.sh
#   bash scripts/memory-curator.sh --days 7
#   bash scripts/memory-curator.sh --since 2026-04-20
#
# Heuristics: scans memory/YYYY-MM-DD*.md within the window, splits each file
# into paragraph chunks (blank-line separated), keeps chunks whose text matches
# durable-signal phrases (lessons learned, decisions, "rule:", "next time",
# "I should", "from now on") or chunks immediately followed by a `**Why:**`
# line. Skips chunks whose source range is already covered by an
# `<!-- openclaw-memory-promotion:memory:<path>:<start>:<end> -->` marker in
# MEMORY.md (overlap match — any byte intersection counts).

set -uo pipefail

WORKSPACE="/root/.openclaw/workspace"
MEMORY_DIR="$WORKSPACE/memory"
MEMORY_FILE="$WORKSPACE/MEMORY.md"

DAYS=14
SINCE=""

while [ "$#" -gt 0 ]; do
  case "$1" in
    --days)
      DAYS="${2:-}"; shift 2 ;;
    --since)
      SINCE="${2:-}"; shift 2 ;;
    -h|--help)
      sed -n '2,18p' "$0" >&2
      exit 0 ;;
    *)
      echo "memory-curator: unknown arg: $1" >&2
      exit 2 ;;
  esac
done

if [ -n "$SINCE" ]; then
  cutoff_epoch=$(date -u -d "$SINCE" +%s 2>/dev/null || true)
  if [ -z "$cutoff_epoch" ]; then
    echo "memory-curator: --since must be YYYY-MM-DD" >&2
    exit 2
  fi
else
  cutoff_epoch=$(date -u -d "$DAYS days ago" +%s)
fi

if [ ! -d "$MEMORY_DIR" ]; then
  echo "memory-curator: $MEMORY_DIR not found"
  exit 0
fi

# Collect already-promoted ranges from MEMORY.md as "path<TAB>start<TAB>end".
PROMOTED=$(mktemp)
trap 'rm -f "$PROMOTED" "$CANDIDATES" 2>/dev/null || true' EXIT
: > "$PROMOTED"
if [ -f "$MEMORY_FILE" ]; then
  grep -oE '<!-- openclaw-memory-promotion:memory:[^[:space:]]+:[0-9]+:[0-9]+ -->' "$MEMORY_FILE" 2>/dev/null \
  | sed -E 's|<!-- openclaw-memory-promotion:memory:([^:]+):([0-9]+):([0-9]+) -->|\1\t\2\t\3|' \
  > "$PROMOTED" || true
fi

already_promoted() {
  # args: path start end
  local p="$1" s="$2" e="$3"
  awk -F'\t' -v p="$p" -v s="$s" -v e="$e" '
    $1==p && !($3 < s || $2 > e) { found=1; exit }
    END { exit found ? 0 : 1 }
  ' "$PROMOTED"
}

# Collect daily-log files within window. Match memory/YYYY-MM-DD*.md.
files=()
shopt -s nullglob
for f in "$MEMORY_DIR"/[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]*.md; do
  base=$(basename "$f")
  date_part="${base:0:10}"
  file_epoch=$(date -u -d "$date_part" +%s 2>/dev/null || echo 0)
  if [ "$file_epoch" -ge "$cutoff_epoch" ]; then
    files+=("$f")
  fi
done
shopt -u nullglob

if [ "${#files[@]}" -eq 0 ]; then
  echo "memory-curator: no daily logs in window (since $(date -u -d "@$cutoff_epoch" +%F))"
  echo "No candidates."
  exit 0
fi

CANDIDATES=$(mktemp)
: > "$CANDIDATES"

# Pattern: durable-signal phrases. Case-insensitive.
# Each pattern carries a tag returned as rationale.
detect_signal() {
  local text="$1"
  local lc
  lc=$(printf '%s' "$text" | tr '[:upper:]' '[:lower:]')
  case "$lc" in
    *"rule:"*)         echo "contains 'rule:'"; return 0 ;;
    *"next time"*)     echo "contains 'next time'"; return 0 ;;
    *"from now on"*)   echo "contains 'from now on'"; return 0 ;;
    *"i should"*)      echo "contains 'I should'"; return 0 ;;
    *"lesson learned"*|*"lessons learned"*)
                       echo "contains 'lesson learned'"; return 0 ;;
    *"decision:"*)     echo "contains 'decision:'"; return 0 ;;
    *"decided to"*)    echo "contains 'decided to'"; return 0 ;;
    *"the rule is"*)   echo "contains 'the rule is'"; return 0 ;;
  esac
  return 1
}

# Parse one file into paragraph chunks (blank-line delimited). For each chunk,
# emit signal hits + chunks whose immediately-following non-blank chunk starts
# with `**Why:**`.
process_file() {
  local f="$1"
  awk '
    BEGIN { chunk=""; start=0; line=0 }
    {
      line++
      if ($0 ~ /^[[:space:]]*$/) {
        if (chunk != "") {
          # emit: start \t end \t chunk (newline-escaped via \x01)
          gsub(/\x01/, " ", chunk)
          printf "%d\x02%d\x02%s\n", start, line-1, chunk
        }
        chunk=""; start=0
      } else {
        if (chunk == "") { start=line }
        if (chunk == "") { chunk=$0 } else { chunk=chunk "\x01" $0 }
      }
    }
    END {
      if (chunk != "") {
        gsub(/\x01/, " ", chunk)
        printf "%d\x02%d\x02%s\n", start, line, chunk
      }
    }
  ' "$f"
}

total=0
for f in "${files[@]}"; do
  rel="memory/$(basename "$f")"
  # Build array of chunks for this file so we can look ahead for **Why:** chunks.
  mapfile -t chunks < <(process_file "$f")
  n=${#chunks[@]}
  for (( i=0; i<n; i++ )); do
    IFS=$'\x02' read -r start end body <<< "${chunks[$i]}"
    [ -z "${start:-}" ] && continue
    [ -z "${body:-}" ] && continue

    rationale=""
    if rationale=$(detect_signal "$body"); then
      :
    else
      # Look at the next chunk: if it begins with `**Why:**`, this chunk is a
      # decision/claim with explicit reasoning attached — promotion-worthy.
      next_idx=$((i+1))
      if [ "$next_idx" -lt "$n" ]; then
        IFS=$'\x02' read -r nstart nend nbody <<< "${chunks[$next_idx]}"
        case "$nbody" in
          '**Why:**'*|'  **Why:**'*|'- **Why:**'*)
            rationale="followed by **Why:**" ;;
        esac
      fi
    fi
    [ -z "$rationale" ] && continue

    if already_promoted "$rel" "$start" "$end"; then
      continue
    fi

    # Format preview: collapse newlines to spaces, truncate to 200 chars.
    preview=$(printf '%s' "$body" | tr '\n' ' ' | sed 's/  */ /g')
    if [ "${#preview}" -gt 200 ]; then
      preview="${preview:0:200}..."
    fi

    printf '%s:%s-%s\t%s\t%s\n' "$rel" "$start" "$end" "$rationale" "$preview" >> "$CANDIDATES"
    total=$((total + 1))
  done
done

if [ "$total" -eq 0 ]; then
  echo "memory-curator: window since $(date -u -d "@$cutoff_epoch" +%F), files=${#files[@]}"
  echo "No candidates."
  exit 0
fi

echo "memory-curator: window since $(date -u -d "@$cutoff_epoch" +%F), files=${#files[@]}, candidates=$total"
echo
i=0
while IFS=$'\t' read -r src rationale preview; do
  i=$((i+1))
  echo "[$i] $src"
  echo "    rationale: $rationale"
  echo "    preview:   $preview"
  echo
done < "$CANDIDATES"

echo "memory-curator: $total candidate(s) — promote by editing $MEMORY_FILE manually." >&2
exit 0
