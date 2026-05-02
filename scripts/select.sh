#!/usr/bin/env bash
# select.sh — SEPL Select step.
# Reads a reflect review sidecar, extracts unchecked next-step candidates and
# hypotheses, scores each via cheap heuristics, writes ranked list to
# reports/select-<date>.md. No LLM call; deterministic.
#
# Usage:
#   scripts/select.sh                # auto-pick newest review sidecar
#   scripts/select.sh <review-file>  # explicit
#
# Exit: 0 ok, 2 nothing to select, 3 input error.
set -euo pipefail

WORKSPACE="/root/.openclaw/workspace"
REPORTS="$WORKSPACE/reports"
TODAY="$(date -u +%Y-%m-%d)"

input="${1:-}"
if [ -z "$input" ]; then
  input=$(ls -t "$REPORTS"/reflect-*-review.md 2>/dev/null | head -1)
fi
if [ -z "$input" ] || [ ! -f "$input" ]; then
  echo "select: no review sidecar found (looked at $REPORTS/reflect-*-review.md)" >&2
  exit 3
fi

review_date=$(basename "$input" | sed -E 's/^reflect-([0-9]{4}-[0-9]{2}-[0-9]{2})-review\.md$/\1/')
out="$REPORTS/select-$TODAY.md"

if ! bash "$WORKSPACE/scripts/guards/review-shape.sh" "$input" >&2; then
  echo "select: refusing invalid review sidecar $input" >&2
  exit 3
fi

# Extract unchecked next-step lines:  "- [ ] body"  → keep body.
# Multi-line candidates (continuation indented) are folded onto one line.
mapfile -t raw < <(awk '
  /^[[:space:]]*-[[:space:]]*\[[[:space:]]\][[:space:]]/ {
    if (cur != "") print cur
    sub(/^[[:space:]]*-[[:space:]]*\[[[:space:]]\][[:space:]]+/, "", $0)
    cur = $0; next
  }
  /^[[:space:]]+[^-[:space:]]/ && cur != "" {
    sub(/^[[:space:]]+/, " ", $0); cur = cur $0; next
  }
  /^[[:space:]]*$/ || /^[[:space:]]*-/ || /^#/ {
    if (cur != "") { print cur; cur = "" }
  }
  END { if (cur != "") print cur }
' "$input")

if [ "${#raw[@]}" -eq 0 ]; then
  echo "select: no unchecked '- [ ]' candidates found in $input" >&2
  exit 2
fi

# Filter out shape-violating candidates (rerun/audit/observation tautologies).
# 2026-04-30: Track 4 burned a cycle on "Re-run the failing fixture set" because
# nothing rejected non-implementable candidates upstream of improve.sh.
filtered=()
shape_guard="$WORKSPACE/scripts/guards/candidate-shape.sh"
if [ -x "$shape_guard" ]; then
  for body in "${raw[@]}"; do
    if bash "$shape_guard" "$body" >/dev/null 2>&1; then
      filtered+=("$body")
    else
      echo "select: dropping shape-violating candidate: $body" >&2
    fi
  done
  if [ "${#filtered[@]}" -eq 0 ]; then
    echo "select: all candidates failed candidate-shape guard — nothing implementable in $input" >&2
    exit 2
  fi
  raw=("${filtered[@]}")
fi

# Compute fixture-redness streak map: for each fixture, count consecutive
# FAIL runs from the newest summary.tsv backward, stopping at the first
# PASS. Walks at most last 14 runs. Output is `<fixture>\t<streak>` per
# line; absent → no streak. Drives the `red` scoring component below so
# Select prefers candidates aimed at long-failing fixtures over freshly
# red ones (e.g., `one-shot-cron-recognition` 13d > `layer-confusion` 1d).
redness_map="$(mktemp)"
runs=()
while IFS= read -r d; do
  [ -f "$d/summary.tsv" ] || continue
  runs+=("$d/summary.tsv")
done < <(ls -1dr "$WORKSPACE/evals/runs/"*/ 2>/dev/null | head -14)
if [ "${#runs[@]}" -gt 0 ]; then
  awk '
    FNR==1 { next }
    {
      fix=$1; res=$2
      if (!(fix in seen)) { seen[fix]=1 }
      hist[fix] = hist[fix] (res == "FAIL" ? "F" : "P")
    }
    END {
      for (f in seen) {
        h = hist[f]; streak = 0
        for (j=1; j<=length(h); j++) {
          if (substr(h, j, 1) == "F") streak++; else break
        }
        if (streak > 0) print f "\t" streak
      }
    }
  ' "${runs[@]}" > "$redness_map"
fi

# Cheap scoring heuristics. Each candidate gets:
#   reversibility   — high if it touches scripts/hooks/evals (revertable);
#                     low if it edits memory/SOUL/AGENTS (rule changes).
#   eval_coverage   — high if mentions evals/fixture/grader/regex/judge;
#                     low if it's a pure runtime change with no test surface.
#   token_burn      — high if mentions a number×count pattern ("3×/day",
#                     "Nx", "8/day") or names a deterministic-conversion target.
#   risk            — bumped up if mentions auto-merge, master, force, delete.
#   redness         — sum of consecutive-fail streaks for fixtures named in
#                     body, capped at 14. Long-red beats fresh-red so we stop
#                     orbiting yesterday's regression and chase the actually-
#                     stuck fixtures.
#   noop            — flag for self-referential placeholder candidates
#                     ("no-op hypothesis", "logging the no-op", "re-run
#                     tomorrow"). Penalized so the green-day stub doesn't
#                     keep winning against real candidates on quiet days.
score_one() {
  local body="$1"
  local rev=2 cov=2 burn=1 risk=0 red=0 noop=0
  # reversibility
  echo "$body" | grep -qiE '(scripts/|hooks/|evals/|fixture)' && rev=3
  echo "$body" | grep -qiE '(SOUL\.md|AGENTS\.md|MEMORY\.md|memory/|USER\.md)' && rev=1
  # eval coverage
  echo "$body" | grep -qiE '(eval|fixture|grader|regex|judge|harness)' && cov=3
  echo "$body" | grep -qiE '(no eval|untested|manual only)' && cov=1
  # token burn signal
  echo "$body" | grep -qiE '([0-9]+[[:space:]]*[xX×][[:space:]]*/?[[:space:]]*(day|wk|week))' && burn=3
  echo "$body" | grep -qiE '(token.burn|deterministic|repeated|recurring)' && burn=$((burn + 1))
  # risk modifiers
  echo "$body" | grep -qiE '(auto.?merge|force.?push|rm.?-rf|delete[[:space:]]+[a-z]+\.md|drop[[:space:]]+table)' && risk=2
  echo "$body" | grep -qiE '(audit|measure|count|read.only|dry.run)' && risk=$((risk - 1))
  # redness: sum streaks for any fixture named in body. Word-boundary match
  # so `layer-confusion` doesn't accidentally pull `non-layer-confusion`.
  if [ -s "$redness_map" ]; then
    while IFS=$'\t' read -r fix streak; do
      [ -n "$fix" ] || continue
      if echo "$body" | grep -qE "\\b${fix}\\b"; then
        red=$((red + streak))
      fi
    done < "$redness_map"
    [ "$red" -gt 14 ] && red=14
  fi
  # noop demotion
  echo "$body" | grep -qiE '(no.?op hypothesis|no change selected|placeholder|logging the no.op|re-run.*tomorrow)' && noop=1
  # composite. weight: red x3 (heaviest — chase oldest pain), burn x2, cov x2,
  # rev x1; subtract risk + noop x5 (effectively excludes noop placeholders).
  local total=$(( red * 3 + burn * 2 + cov * 2 + rev - risk - noop * 5 ))
  printf "%d\t%d\t%d\t%d\t%d\t%d\t%d\n" "$total" "$burn" "$cov" "$rev" "$risk" "$red" "$noop"
}

slugify() {
  echo "$1" \
    | tr '[:upper:]' '[:lower:]' \
    | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//' \
    | cut -c1-50
}

# Score every candidate, sort desc, take top N.
N="${SELECT_N:-3}"
tmp="$(mktemp)"
trap 'rm -f "$tmp" "$redness_map"' EXIT
i=0
for body in "${raw[@]}"; do
  scores=$(score_one "$body")
  total=$(echo "$scores" | cut -f1)
  rest=$(echo "$scores" | cut -f2-)
  slug=$(slugify "$body")
  printf "%d\t%d\t%s\t%s\t%s\n" "$total" "$i" "$slug" "$rest" "$body" >> "$tmp"
  i=$((i + 1))
done

# header
{
  echo "# Select — $TODAY"
  echo
  echo "_Generated by \`scripts/select.sh\` from \`$(basename "$input")\` (review of $review_date)._"
  echo "_SEPL step 2/5. Heuristic scoring; no LLM call. Top $N candidates by composite score._"
  echo "_Historical selection snapshot: this file captures the candidate ranking at generation time. Treat \`backlog.jsonl\`, the latest reflect review, and current repo state as live truth._"
  echo
  echo "## Ranked candidates"
  echo
  echo "| Rank | ID | Score | burn | cov | rev | risk | red | noop | Title |"
  echo "|------|----|-------|------|-----|-----|------|-----|------|-------|"
  rank=0
  while IFS=$'\t' read -r total idx slug burn cov rev risk red noop body; do
    rank=$((rank + 1))
    [ "$rank" -gt "$N" ] && break
    title=$(echo "$body" | cut -c1-80 | tr -d '|')
    printf "| %d | %s | %d | %d | %d | %d | %d | %d | %d | %s |\n" \
      "$rank" "$slug" "$total" "$burn" "$cov" "$rev" "$risk" "$red" "$noop" "$title"
  done < <(sort -k1,1 -nr "$tmp")
  echo
  echo "## Candidate detail"
  echo
  rank=0
  while IFS=$'\t' read -r total idx slug burn cov rev risk red noop body; do
    rank=$((rank + 1))
    [ "$rank" -gt "$N" ] && break
    echo "### $rank. \`$slug\`  (score=$total)"
    echo
    echo "**Original line:**"
    echo
    echo "> $body"
    echo
    echo "- token_burn=$burn, eval_coverage=$cov, reversibility=$rev, risk=$risk, redness=$red, noop=$noop"
    echo "- next: \`scripts/improve.sh $(basename "$0" .sh | sed 's/^select/select/')-$TODAY $slug\`"
    echo
  done < <(sort -k1,1 -nr "$tmp")
  echo "---"
  echo
  echo "_Total raw candidates considered: ${#raw[@]}_"
  echo "_Source: ${input}_"
} > "$out"

echo "wrote $out (top $N of ${#raw[@]} candidates from $(basename "$input"))"
