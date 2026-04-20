#!/usr/bin/env bash
# Turn a mistakes.md entry into a draft eval fixture. Pulls the section
# under a given heading anchor, extracts the "Lesson" line as the rubric
# stub, and drops a fixture draft at evals/fixtures-draft/<slug>.json for
# manual review. Closes the Reflect → Evaluate loop: every confident-wrong
# claim can become a regression test.
#
# Usage:
#   bash scripts/mistake-to-fixture.sh "gitignore-negation"
#   bash scripts/mistake-to-fixture.sh --list
set -uo pipefail

WORKSPACE="/root/.openclaw/workspace"
MISTAKES="$WORKSPACE/reports/mistakes.md"
DRAFT_DIR="$WORKSPACE/evals/fixtures-draft"

if [ ! -f "$MISTAKES" ]; then
  echo "mistake-to-fixture: $MISTAKES not found" >&2
  exit 1
fi

mkdir -p "$DRAFT_DIR"

# --list mode: show anchor candidates from level-3 headings
if [ "${1:-}" = "--list" ] || [ -z "${1:-}" ]; then
  echo "Available mistake anchors (use slug form as arg):"
  grep -nE '^### ' "$MISTAKES" | sed -E 's/^([0-9]+):### (.*)$/  \1: \2/'
  exit 0
fi

QUERY="$1"
# Pull the section: find ### line matching QUERY (case-insensitive),
# then content until next ### or ## or EOF.
SECTION=$(awk -v q="$QUERY" '
  BEGIN { in_section=0; IGNORECASE=1 }
  /^### / {
    if (in_section) exit;
    if (tolower($0) ~ tolower(q)) { in_section=1; print; next }
  }
  /^## [^#]/ { if (in_section) exit }
  in_section { print }
' "$MISTAKES")

if [ -z "$SECTION" ]; then
  echo "mistake-to-fixture: no section matching '$QUERY'" >&2
  echo "Run with --list to see available anchors." >&2
  exit 1
fi

# Extract the "Lesson:" / "Why wrong:" / "Fix:" lines as rubric inputs.
# Fallback to first prose line.
LESSON=$(printf '%s\n' "$SECTION" | grep -E '^\*\*(Lesson|Why wrong|Fix)\*\*' | head -3 | sed -E 's/^\*\*[^*]+\*\*[[:space:]]*//')
if [ -z "$LESSON" ]; then
  LESSON=$(printf '%s\n' "$SECTION" | grep -vE '^(###|\*\*|$)' | head -3 | tr '\n' ' ')
fi

# Slug from heading (lowercase, alnum+dash)
HEADING=$(printf '%s' "$SECTION" | head -1 | sed -E 's/^### [0-9:]+[[:space:]]*—?[[:space:]]*//')
SLUG=$(printf '%s' "$HEADING" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/-/g; s/^-+|-+$//g' | cut -c1-60)
[ -z "$SLUG" ] && SLUG=$(printf '%s' "$QUERY" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/-/g')

OUT="$DRAFT_DIR/${SLUG}.json"

# Construct the fixture. Prompt is a placeholder — the human reviewer
# must rewrite it to something that actually triggers the behavior. The
# rubric is pre-filled from the lesson text.
jq -n \
  --arg name "$SLUG" \
  --arg desc "Drafted from mistakes.md entry: $HEADING" \
  --arg prompt "TODO: write a prompt that would have triggered the original mistake. (Drafted $(date -u +%FT%TZ) from $HEADING)" \
  --arg rubric "The response must avoid the mistake: $LESSON" \
  '{
    name: $name,
    description: $desc,
    prompt: $prompt,
    graders: [
      {
        type: "llm_judge",
        rubric: $rubric
      }
    ],
    _draft: {
      source: "reports/mistakes.md",
      anchor: $name,
      needs_review: [
        "Rewrite prompt to actually trigger the original failure mode",
        "Add regex_negative patterns if the mistake has textual fingerprints",
        "Add tool_sequence_contains if the mistake involves wrong/missing tools"
      ]
    }
  }' > "$OUT"

echo "mistake-to-fixture: wrote $OUT"
echo ""
echo "--- draft ---"
jq -r '. | "name: \(.name)\ndescription: \(.description)\nrubric: \(.graders[0].rubric)"' "$OUT"
echo ""
echo "Review + edit the prompt, then move to evals/fixtures/ to activate."
