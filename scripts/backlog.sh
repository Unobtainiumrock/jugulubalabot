#!/usr/bin/env bash
# Persistent backlog queue for joint work between God and Tai. Survives /new,
# survives reboots, survives session churn. Lightweight JSONL store.
#
# Subcommands:
#   add <priority> "title"   — append open item; priority in {low,medium,high}
#   ls [status]              — list (default: open+doing; status=all shows everything)
#   start <id>               — mark status=doing
#   done <id>                — mark status=done
#   drop <id>                — mark status=dropped (with reason if given)
#   note <id> "text"         — append a note to an item
#   show <id>                — full JSON for one item
#
# Data at workspace/backlog.jsonl (gitignored — high-churn agent state).
# IDs are 6-char prefix of sha256(title+ts_created).

set -uo pipefail

WORKSPACE="/root/.openclaw/workspace"
BACKLOG="$WORKSPACE/backlog.jsonl"
mkdir -p "$(dirname "$BACKLOG")"
touch "$BACKLOG"

CMD="${1:-ls}"
shift || true

ts() { date -u +%Y-%m-%dT%H:%M:%SZ; }

gen_id() {
  local title=$1 tsval=$2
  printf '%s' "${title}${tsval}" | sha256sum | cut -c1-6
}

case "$CMD" in
  add)
    priority="${1:-medium}"
    shift || true
    title="${*:-}"
    if [ -z "$title" ]; then echo "Usage: backlog.sh add <priority> \"title\"" >&2; exit 2; fi
    if [[ "$priority" != "low" && "$priority" != "medium" && "$priority" != "high" ]]; then
      echo "priority must be low|medium|high (got '$priority')" >&2; exit 2
    fi
    ts_now=$(ts)
    id=$(gen_id "$title" "$ts_now")
    jq -cn --arg id "$id" --arg ts "$ts_now" --arg p "$priority" --arg t "$title" \
      '{id:$id, ts_created:$ts, ts_updated:$ts, status:"open", priority:$p, title:$t, notes:[]}' \
      >> "$BACKLOG"
    echo "Added $id [$priority]: $title"
    ;;

  ls)
    filter="${1:-active}"
    case "$filter" in
      all)     jq_filter='.' ;;
      active)  jq_filter='select(.status == "open" or .status == "doing")' ;;
      *)       jq_filter="select(.status == \"$filter\")" ;;
    esac
    # Pretty table output
    jq -r "$jq_filter | [.id, .status, .priority, .title] | @tsv" "$BACKLOG" 2>/dev/null \
      | awk -F'\t' 'BEGIN{printf "%-7s %-8s %-7s %s\n", "ID", "STATUS", "PRIO", "TITLE"; printf "%-7s %-8s %-7s %s\n", "-------", "--------", "-------", "----------"} {printf "%-7s %-8s %-7s %s\n", $1, $2, $3, $4}'
    COUNT=$(jq -c "$jq_filter" "$BACKLOG" 2>/dev/null | wc -l | tr -d ' ')
    echo ""
    echo "($COUNT items)"
    ;;

  start|done|drop)
    id="${1:-}"
    if [ -z "$id" ]; then echo "Usage: backlog.sh $CMD <id>" >&2; exit 2; fi
    new_status="$CMD"
    [ "$CMD" = "start" ] && new_status="doing"
    [ "$CMD" = "done" ]  && new_status="done"
    [ "$CMD" = "drop" ]  && new_status="dropped"
    tmp=$(mktemp)
    found=0
    ts_now=$(ts)
    while IFS= read -r line; do
      row_id=$(printf '%s' "$line" | jq -r '.id')
      if [ "$row_id" = "$id" ]; then
        updated=$(printf '%s' "$line" | jq -c --arg s "$new_status" --arg t "$ts_now" '.status = $s | .ts_updated = $t')
        printf '%s\n' "$updated" >> "$tmp"
        found=1
      else
        printf '%s\n' "$line" >> "$tmp"
      fi
    done < "$BACKLOG"
    if [ "$found" -eq 0 ]; then
      rm -f "$tmp"
      echo "No backlog item with id '$id'" >&2; exit 1
    fi
    mv "$tmp" "$BACKLOG"
    echo "$id → $new_status"
    ;;

  note)
    id="${1:-}"
    shift || true
    text="${*:-}"
    if [ -z "$id" ] || [ -z "$text" ]; then echo "Usage: backlog.sh note <id> \"text\"" >&2; exit 2; fi
    tmp=$(mktemp)
    found=0
    ts_now=$(ts)
    while IFS= read -r line; do
      row_id=$(printf '%s' "$line" | jq -r '.id')
      if [ "$row_id" = "$id" ]; then
        updated=$(printf '%s' "$line" | jq -c --arg t "$ts_now" --arg n "$text" \
          '.notes += [{ts:$t, text:$n}] | .ts_updated = $t')
        printf '%s\n' "$updated" >> "$tmp"
        found=1
      else
        printf '%s\n' "$line" >> "$tmp"
      fi
    done < "$BACKLOG"
    if [ "$found" -eq 0 ]; then
      rm -f "$tmp"
      echo "No backlog item with id '$id'" >&2; exit 1
    fi
    mv "$tmp" "$BACKLOG"
    echo "Note added to $id"
    ;;

  show)
    id="${1:-}"
    if [ -z "$id" ]; then echo "Usage: backlog.sh show <id>" >&2; exit 2; fi
    jq -r --arg id "$id" 'select(.id == $id)' "$BACKLOG"
    ;;

  *)
    echo "Usage: $(basename "$0") {add|ls|start|done|drop|note|show} ..." >&2
    echo "" >&2
    echo "Examples:" >&2
    echo "  $(basename "$0") add high \"Fix class extractor brittleness\"" >&2
    echo "  $(basename "$0") ls" >&2
    echo "  $(basename "$0") start abc123" >&2
    exit 2
    ;;
esac
