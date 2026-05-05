#!/usr/bin/env bash
# soul-rule-proposer — cluster reports/mistakes.md entries by symptom keywords
# and propose SOUL.md bullet stubs (rule + Why + How to apply) for clusters
# of size >= MIN_CLUSTER. Output is stdout-only; never edits SOUL.md.
#
# Usage:
#   bash scripts/soul-rule-proposer.sh
#   bash scripts/soul-rule-proposer.sh --min-cluster 4
#
# Notes:
#   - Pure bash + awk. Python avoided to keep the dependency surface zero
#     and let this run from any heartbeat/cron context without a venv.
#   - Defensive on missing input file; exits 0 in all benign cases.
#   - Does NOT auto-write to SOUL.md. Humans review before any rule lands.

set -uo pipefail

WORKSPACE="${WORKSPACE:-/root/.openclaw/workspace}"
MISTAKES="${MISTAKES_FILE:-$WORKSPACE/reports/mistakes.md}"
MIN_CLUSTER=3

while [ "$#" -gt 0 ]; do
  case "$1" in
    --min-cluster)
      MIN_CLUSTER="${2:-3}"
      shift 2
      ;;
    --min-cluster=*)
      MIN_CLUSTER="${1#*=}"
      shift
      ;;
    -h|--help)
      sed -n '1,16p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *)
      echo "soul-rule-proposer: unknown arg: $1" >&2
      exit 2
      ;;
  esac
done

if [ ! -f "$MISTAKES" ]; then
  echo "soul-rule-proposer: $MISTAKES not found — nothing to cluster."
  echo "soul-rule-proposer: missing input, exit 0" >&2
  exit 0
fi

TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

ENTRIES_DIR="$TMPDIR/entries"
mkdir -p "$ENTRIES_DIR"

# Pass 1: split mistakes.md into per-entry files. An entry begins at a
# `### HH:MM` header and runs until the next `### ` header or `---` line.
# Track the most recent `## YYYY-MM-DD` section as the entry's date.
awk -v outdir="$ENTRIES_DIR" '
  BEGIN { idx = 0; date = "unknown"; in_entry = 0; }
  /^## [0-9]{4}-[0-9]{2}-[0-9]{2}/ {
    # Date section header. Capture date token.
    split($0, a, " ");
    date = a[2];
    if (in_entry) { close(out); in_entry = 0; }
    next;
  }
  /^### / {
    if (in_entry) { close(out); }
    idx++;
    out = sprintf("%s/%04d.entry", outdir, idx);
    header = $0;
    sub(/^### /, "", header);
    print "DATE:" date > out;
    print "HEADER:" header >> out;
    print "BODY_START" >> out;
    in_entry = 1;
    next;
  }
  /^---[[:space:]]*$/ {
    if (in_entry) { close(out); in_entry = 0; }
    next;
  }
  {
    if (in_entry) print $0 >> out;
  }
  END {
    if (in_entry) close(out);
  }
' "$MISTAKES"

ENTRY_COUNT=$(ls "$ENTRIES_DIR" 2>/dev/null | wc -l)

if [ "$ENTRY_COUNT" -eq 0 ]; then
  echo "soul-rule-proposer: $MISTAKES has no parseable entries (no '### HH:MM' headers)."
  echo "soul-rule-proposer: 0 entries parsed, exit 0" >&2
  exit 0
fi

# Pass 2: for each entry, extract tokens from the header and the
# "Why wrong" block. Lowercase, strip punctuation, drop stopwords/short
# tokens, dedupe.

STOPWORDS=" the a an is of to that this it was were be been being am are i my me we us our you your he she his her they them their for in on at by with from as and or but not no yes if then else when while because so just like also too very can could would should did do does done not n have has had get got going go went come came make made take took say said think thought see saw know knew way thing things use used one two three first second next any all some each every other another only own same own such these those who whom what which where there here why how its hers ours theirs into onto off out up down again still already always never either neither than then though although while between among about against without within across after before during over under up down toward upon however therefore however thus already such still still very real much more less most least many few several both either neither each both off file files line lines memory rule rules code text step steps mode path paths name names check checked checking item items entry entries fact facts case cases note notes failure failures actually actual model models true real reason reasons issue issues moment moments answer answers belief beliefs claim claims state states fix fixes fixed durable point points pointer pointers script scripts hook hooks instead within without bullet bullets section sections content contents call calls runtime ran "

TOKENS_DIR="$TMPDIR/tokens"
mkdir -p "$TOKENS_DIR"

# Helper awk that emits unique non-stopword tokens >=4 chars from stdin.
# Stopwords are passed via -v sw.
extract_tokens() {
  awk -v sw="$STOPWORDS" '
    BEGIN {
      # Build a hash of stopwords from the spaced string.
      n = split(sw, swarr, " ");
      for (i = 1; i <= n; i++) stop[swarr[i]] = 1;
    }
    {
      # Lowercase + replace any non-alnum with space.
      line = tolower($0);
      gsub(/[^a-z0-9]+/, " ", line);
      m = split(line, w, " ");
      for (i = 1; i <= m; i++) {
        t = w[i];
        if (length(t) < 4) continue;
        if (t in stop) continue;
        # Strip trailing pluralish s for crude stemming.
        if (length(t) > 5 && substr(t, length(t)) == "s") {
          stem = substr(t, 1, length(t) - 1);
        } else {
          stem = t;
        }
        seen[stem] = 1;
      }
    }
    END {
      for (k in seen) print k;
    }
  '
}

for entry in "$ENTRIES_DIR"/*.entry; do
  base="$(basename "$entry" .entry)"
  # Extract header (after "HEADER:").
  header_line=$(awk -F'HEADER:' '/^HEADER:/ { sub(/^HEADER:/, ""); print; exit }' "$entry")
  # Header symptom: portion after the first " — " or " - " dash.
  symptom="$header_line"
  if echo "$header_line" | grep -q ' — '; then
    symptom="${header_line#* — }"
  elif echo "$header_line" | grep -q ' - '; then
    symptom="${header_line#* - }"
  fi
  # Extract Why wrong block (between **Why wrong:** and next blank line / next ** field).
  why_block=$(awk '
    BEGIN { capture = 0; }
    /^\*\*Why wrong:\*\*/ { capture = 1; sub(/^\*\*Why wrong:\*\*/, ""); print; next; }
    capture && /^\*\*[A-Z]/ { capture = 0; }
    capture && /^---/ { capture = 0; }
    capture { print; }
  ' "$entry")

  # Extract Fix block similarly (used for "How to apply:" inference).
  fix_block=$(awk '
    BEGIN { capture = 0; }
    /^\*\*Fix:\*\*/ || /^\*\*Durable fix:\*\*/ { capture = 1; sub(/^\*\*[^*]+\*\*/, ""); print; next; }
    capture && /^\*\*[A-Z]/ { capture = 0; }
    capture && /^---/ { capture = 0; }
    capture { print; }
  ' "$entry")

  has_fix=0
  if [ -n "$fix_block" ]; then has_fix=1; fi

  # Token source: symptom + why_block (header symptom heavily weighted by also
  # being the cluster name source).
  {
    echo "$symptom"
    echo "$why_block"
  } | extract_tokens > "$TOKENS_DIR/$base.tok"

  # Save metadata sidecar.
  date_line=$(awk -F'DATE:' '/^DATE:/ { sub(/^DATE:/, ""); print; exit }' "$entry")
  # Time token: prefer the first HH:MM-shaped substring in the header.
  # Falls back to the first whitespace-delimited word if none found
  # (so a malformed header still emits something readable).
  time_token=$(echo "$header_line" | awk '{
    for (i = 1; i <= NF; i++) {
      if ($i ~ /^[0-9]{1,2}:[0-9]{2}/) { print $i; exit }
    }
    print $1;
  }')
  # If header opens with an ISO date (### 2026-04-22 00:47 UTC — ...),
  # promote that date over the section date so the entry is labeled by
  # its own date stamp.
  iso_in_header=$(echo "$header_line" | awk '{
    if ($1 ~ /^[0-9]{4}-[0-9]{2}-[0-9]{2}$/) print $1;
  }')
  if [ -n "$iso_in_header" ]; then
    date_line="$iso_in_header"
  fi
  {
    echo "DATE=$date_line"
    echo "TIME=$time_token"
    echo "SYMPTOM=$symptom"
    echo "HAS_FIX=$has_fix"
  } > "$TOKENS_DIR/$base.meta"

  # Cache why+fix snippets for proposal generation.
  echo "$why_block" > "$TOKENS_DIR/$base.why"
  echo "$fix_block" > "$TOKENS_DIR/$base.fix"
done

# Pass 3: cluster. Two entries cluster if they share >= 2 non-stopword
# tokens. Use single-link agglomerative: union-find by entry index.

ENTRIES=()
for f in "$TOKENS_DIR"/*.tok; do
  ENTRIES+=("$(basename "$f" .tok)")
done

N=${#ENTRIES[@]}

# parent[i] = i initially (union-find)
declare -a PARENT
for ((i = 0; i < N; i++)); do PARENT[i]=$i; done

find_root() {
  local x="$1"
  while [ "${PARENT[$x]}" != "$x" ]; do
    PARENT[$x]="${PARENT[${PARENT[$x]}]}"
    x="${PARENT[$x]}"
  done
  echo "$x"
}

union_idx() {
  local ra rb
  ra=$(find_root "$1")
  rb=$(find_root "$2")
  if [ "$ra" != "$rb" ]; then
    PARENT[$ra]=$rb
  fi
}

# For each pair, compute shared token count.
for ((i = 0; i < N; i++)); do
  for ((j = i + 1; j < N; j++)); do
    fa="$TOKENS_DIR/${ENTRIES[$i]}.tok"
    fb="$TOKENS_DIR/${ENTRIES[$j]}.tok"
    shared=$(grep -Fxf "$fa" "$fb" 2>/dev/null | wc -l)
    if [ "$shared" -ge 2 ]; then
      union_idx "$i" "$j"
    fi
  done
done

# Collect clusters by root.
declare -A CLUSTER_OF
for ((i = 0; i < N; i++)); do
  r=$(find_root "$i")
  CLUSTER_OF[$i]=$r
done

# Group cluster members.
declare -A CLUSTER_MEMBERS
for ((i = 0; i < N; i++)); do
  r="${CLUSTER_OF[$i]}"
  if [ -z "${CLUSTER_MEMBERS[$r]+_}" ]; then
    CLUSTER_MEMBERS[$r]="$i"
  else
    CLUSTER_MEMBERS[$r]="${CLUSTER_MEMBERS[$r]} $i"
  fi
done

# Pass 4: emit clusters of size >= MIN_CLUSTER.
HEADER_PRINTED=0
CLUSTERS_FOUND=0

for r in "${!CLUSTER_MEMBERS[@]}"; do
  members=(${CLUSTER_MEMBERS[$r]})
  size=${#members[@]}
  if [ "$size" -lt "$MIN_CLUSTER" ]; then continue; fi

  # Pre-condition: all entries in cluster must have a Fix line. If any
  # entry lacks Fix, skip — we only propose rules from closed-loop signal.
  all_fixed=1
  missing_fix=()
  for m in "${members[@]}"; do
    base="${ENTRIES[$m]}"
    has_fix=$(awk -F= '/^HAS_FIX=/ { print $2 }' "$TOKENS_DIR/$base.meta")
    if [ "$has_fix" != "1" ]; then
      all_fixed=0
      missing_fix+=("$base")
    fi
  done

  CLUSTERS_FOUND=$((CLUSTERS_FOUND + 1))

  if [ "$HEADER_PRINTED" -eq 0 ]; then
    echo "# soul-rule-proposer — cluster report"
    echo
    echo "Source: $MISTAKES"
    echo "Min cluster size: $MIN_CLUSTER"
    echo "Total entries scanned: $N"
    echo
    HEADER_PRINTED=1
  fi

  # Pick a cluster name: top 2 most-frequent shared tokens across members.
  : > "$TMPDIR/cluster.tokpool"
  for m in "${members[@]}"; do
    cat "$TOKENS_DIR/${ENTRIES[$m]}.tok" >> "$TMPDIR/cluster.tokpool"
  done
  cluster_name=$(sort "$TMPDIR/cluster.tokpool" | uniq -c | sort -rn \
    | awk '$1 >= 2 { print $2 }' | head -2 | paste -sd '-' -)
  if [ -z "$cluster_name" ]; then
    cluster_name="mixed-symptoms"
  fi

  echo "## Cluster: $cluster_name ($size entries)"
  echo "Entries:"
  for m in "${members[@]}"; do
    base="${ENTRIES[$m]}"
    d=$(awk -F= '/^DATE=/ { print $2 }' "$TOKENS_DIR/$base.meta")
    t=$(awk -F= '/^TIME=/ { print $2 }' "$TOKENS_DIR/$base.meta")
    s=$(awk -F= '/^SYMPTOM=/ { sub(/^SYMPTOM=/, ""); print }' "$TOKENS_DIR/$base.meta")
    echo "- $d/$t — $s"
  done
  echo

  if [ "$all_fixed" -eq 0 ]; then
    echo "Pre-condition NOT MET: ${#missing_fix[@]} entries in this cluster lack a Fix: line."
    echo "Skipping bullet proposal — only closed-loop clusters earn a SOUL rule."
    echo
    continue
  fi

  # Build proposal: pull one short snippet from why_block, one from fix_block.
  why_snip=""
  fix_snip=""
  for m in "${members[@]}"; do
    base="${ENTRIES[$m]}"
    if [ -z "$why_snip" ]; then
      why_snip=$(tr '\n' ' ' < "$TOKENS_DIR/$base.why" \
        | sed 's/  */ /g' | sed 's/^ *//' | cut -c1-180)
    fi
    if [ -z "$fix_snip" ]; then
      fix_snip=$(tr '\n' ' ' < "$TOKENS_DIR/$base.fix" \
        | sed 's/  */ /g' | sed 's/^ *//' | cut -c1-180)
    fi
  done

  rule_subject=$(echo "$cluster_name" | tr '-' ' ')
  echo "Proposed SOUL bullet:"
  echo "- **Watch for recurring $rule_subject failure mode.** **Why:** $why_snip **How to apply:** $fix_snip"
  echo
done

if [ "$CLUSTERS_FOUND" -eq 0 ]; then
  echo "soul-rule-proposer: scanned $N entries; no clusters of size >= $MIN_CLUSTER."
  echo "Current mistakes are all unique failure modes — no recurring single mode warrants a SOUL bullet yet."
fi

echo "soul-rule-proposer: scanned $N entries, emitted $CLUSTERS_FOUND cluster(s) at min=$MIN_CLUSTER" >&2
