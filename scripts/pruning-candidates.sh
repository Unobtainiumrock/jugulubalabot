#!/usr/bin/env bash
# pruning-candidates.sh — Join file-heat + bash-callgraph + git-age into
# state/pruning-candidates.jsonl. Pure data → data. No network, no model calls.
#
# Flag rule (a file is a candidate iff ALL hold):
#   1. heat < 0.5                       (T_heat — ~one decay half-life of silence)
#   2. fan_in < 1 in bash-callgraph AND path NOT in entrypoint set
#                                       (combined low-centrality check)
#   3. git last-touch age > 30 days     (young-tree tuning)
#
# NOTE: the 30-day threshold is a young-tree setting. Ratchet to 60d on
# 2026-07-01 once the repo is older; grep this file for "60d ratchet" to find
# it. Rationale: at <3 months total repo age, 30d is already 1/3 of history.
#
# Entrypoints are discovered DYNAMICALLY from:
#   - cron payloads (jobs.json message/prompt fields)
#   - scripts/hooks/*.sh
#   - HEARTBEAT.md
#   - ~/.claude/settings*.json
# No hardcoded list. Discovery failures warn-and-continue (graceful degradation).

set -uo pipefail

ROOT="/root/.openclaw/workspace"
STATE="$ROOT/state"
HEAT="$STATE/file-heat.jsonl"
CALLGRAPH="$STATE/bash-callgraph.json"
ENTRYPOINTS_OUT="$STATE/entrypoints.json"
OUT="$STATE/pruning-candidates.jsonl"
NOW_ISO="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
NOW_EPOCH="$(date -u +%s)"

# ---------- preconditions ----------
if [[ ! -s "$HEAT" ]]; then
  echo "pruning-candidates: ERROR — $HEAT missing or empty" >&2
  exit 2
fi

if [[ ! -s "$CALLGRAPH" ]]; then
  echo "pruning-candidates: WARN — $CALLGRAPH missing; treating all non-entrypoint paths as fan_in=0" >&2
fi

mkdir -p "$STATE"

# ---------- entrypoint discovery ----------
# Emit lines like "scripts/foo.sh" onto stdout; dedupe at the end.
tmp_cron=$(mktemp)
tmp_hooks=$(mktemp)
tmp_hb=$(mktemp)
tmp_settings=$(mktemp)
trap 'rm -f "$tmp_cron" "$tmp_hooks" "$tmp_hb" "$tmp_settings"' EXIT

# 1. cron jobs
cron_file="/root/.openclaw/cron/jobs.json"
if [[ -s "$cron_file" ]]; then
  # Concatenate every message+prompt text, then grep for scripts/*.sh substrings.
  if ! jq -r '[.jobs[]? | .payload.message // "", .payload.prompt // ""] | .[]' "$cron_file" 2>/dev/null \
        | grep -oE 'scripts/[A-Za-z0-9_./-]+\.sh' \
        | sort -u > "$tmp_cron"; then
    echo "pruning-candidates: WARN — failed to parse $cron_file" >&2
    : > "$tmp_cron"
  fi
else
  echo "pruning-candidates: WARN — $cron_file missing" >&2
  : > "$tmp_cron"
fi

# 2. hooks
if compgen -G "$ROOT/scripts/hooks/*.sh" > /dev/null; then
  for f in "$ROOT"/scripts/hooks/*.sh; do
    printf 'scripts/hooks/%s\n' "$(basename "$f")"
  done | sort -u > "$tmp_hooks"
else
  : > "$tmp_hooks"
fi

# 3. heartbeat
hb_file="$ROOT/HEARTBEAT.md"
if [[ -s "$hb_file" ]]; then
  grep -oE 'scripts/[A-Za-z0-9_./-]+\.sh' "$hb_file" 2>/dev/null | sort -u > "$tmp_hb" || : > "$tmp_hb"
else
  : > "$tmp_hb"
fi

# 4. Claude Code settings
: > "$tmp_settings"
for s in /root/.claude/settings.json /root/.claude/settings.local.json; do
  if [[ -s "$s" ]]; then
    grep -oE 'scripts/[A-Za-z0-9_./-]+\.sh' "$s" 2>/dev/null >> "$tmp_settings" || true
  fi
done
sort -u "$tmp_settings" -o "$tmp_settings"

# Build entrypoints.json
jq -n \
  --arg generated "$NOW_ISO" \
  --rawfile cron "$tmp_cron" \
  --rawfile hooks "$tmp_hooks" \
  --rawfile hb "$tmp_hb" \
  --rawfile settings "$tmp_settings" \
  '
  def lines: split("\n") | map(select(length > 0));
  {
    generated: $generated,
    sources: {
      cron: ($cron | lines),
      hooks: ($hooks | lines),
      heartbeat: ($hb | lines),
      claude_settings: ($settings | lines)
    }
  }
  | .all = (
      (.sources.cron + .sources.hooks + .sources.heartbeat + .sources.claude_settings)
      | unique
    )
  ' > "$ENTRYPOINTS_OUT"

# In-memory lookup: one path per line, sorted/dedup.
entrypoints_list=$(jq -r '.all[]' "$ENTRYPOINTS_OUT")
entry_count=$(printf '%s\n' "$entrypoints_list" | grep -c . || true)

# ---------- flag loop ----------
# For each heat row: look up fan_in (default 0), compute git_age_days, decide.
: > "$OUT"

flagged=0
total=0

while IFS= read -r row; do
  [[ -z "$row" ]] && continue
  total=$((total + 1))

  path=$(jq -r '.path' <<<"$row")
  heat=$(jq -r '.heat' <<<"$row")
  last_touched_heat=$(jq -r '.last_touched' <<<"$row")

  # heat threshold
  heat_ok=$(awk -v h="$heat" 'BEGIN { print (h < 0.5) ? 1 : 0 }')
  [[ "$heat_ok" == "1" ]] || continue

  # fan_in lookup (default 0 when callgraph missing or path absent)
  if [[ -s "$CALLGRAPH" ]]; then
    fan_in=$(jq -r --arg p "$path" '.nodes[$p].fan_in // 0' "$CALLGRAPH" 2>/dev/null)
    fan_out=$(jq -r --arg p "$path" '.nodes[$p].fan_out // 0' "$CALLGRAPH" 2>/dev/null)
  else
    fan_in=0
    fan_out=0
  fi
  [[ -z "$fan_in" || "$fan_in" == "null" ]] && fan_in=0
  [[ -z "$fan_out" || "$fan_out" == "null" ]] && fan_out=0

  # centrality: fan_in < 1 AND not in entrypoint set
  is_entry=0
  if [[ -n "$entrypoints_list" ]] && printf '%s\n' "$entrypoints_list" | grep -Fxq "$path"; then
    is_entry=1
  fi
  if [[ "$fan_in" -ge 1 ]] || [[ "$is_entry" == "1" ]]; then
    continue
  fi

  # git last-touch age
  last_touched_git=$(git -C "$ROOT" log -1 --format=%cI -- "$path" 2>/dev/null || true)
  if [[ -z "$last_touched_git" ]]; then
    # Untracked — can't attribute, skip.
    continue
  fi
  last_touched_epoch=$(date -u -d "$last_touched_git" +%s 2>/dev/null || echo "")
  if [[ -z "$last_touched_epoch" ]]; then
    continue
  fi
  git_age_days=$(( (NOW_EPOCH - last_touched_epoch) / 86400 ))
  if [[ "$git_age_days" -le 30 ]]; then
    continue
  fi

  last_touched_date="${last_touched_git%%T*}"

  # Build reasons[] with actual measured values.
  reason_heat=$(printf 'heat=%s < 0.5' "$heat")
  if [[ "$is_entry" == "1" ]]; then
    reason_centrality=$(printf 'fan_in=%s and entrypoint=true' "$fan_in")
  else
    reason_centrality=$(printf 'fan_in=%s and not an entrypoint' "$fan_in")
  fi
  reason_age=$(printf 'stale %sd > 30d' "$git_age_days")

  jq -cn \
    --arg path "$path" \
    --argjson heat "$heat" \
    --argjson fi "$fan_in" \
    --argjson fo "$fan_out" \
    --argjson age "$git_age_days" \
    --arg lt "$last_touched_date" \
    --arg r1 "$reason_heat" \
    --arg r2 "$reason_centrality" \
    --arg r3 "$reason_age" \
    '{
       path: $path,
       heat: $heat,
       centrality_fan_in: $fi,
       centrality_fan_out: $fo,
       git_age_days: $age,
       last_touched: $lt,
       reasons: [$r1, $r2, $r3]
     }' >> "$OUT"

  flagged=$((flagged + 1))
done < "$HEAT"

# Sort by heat ascending (coldest first) in place.
if [[ -s "$OUT" ]]; then
  tmp_sorted=$(mktemp)
  jq -s 'sort_by(.heat) | .[]' "$OUT" | jq -c '.' > "$tmp_sorted"
  mv "$tmp_sorted" "$OUT"
fi

echo "pruning-candidates: ${flagged} flagged out of ${total} heat-tracked files (entrypoints excluded: ${entry_count})" >&2
