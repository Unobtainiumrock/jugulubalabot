#!/usr/bin/env bash
# mkscript — write an executable script in one call.
# Usage: scripts/mkscript.sh <path> [mode=0755] <<'EOF'
#          #!/usr/bin/env bash
#          echo hi
#        EOF
# Collapses the Write+chmod pair (flagged in daily reflect) into one Bash tool
# invocation. Stdin is required; an empty body errors out.

set -euo pipefail

if [ "$#" -lt 1 ]; then
  echo "usage: mkscript.sh <path> [mode]" >&2
  exit 2
fi

path="$1"
mode="${2:-0755}"

if [ -t 0 ]; then
  echo "mkscript: stdin is required — pipe or heredoc the script body" >&2
  exit 2
fi

mkdir -p "$(dirname "$path")"
cat > "$path"

if [ ! -s "$path" ]; then
  rm -f "$path"
  echo "mkscript: refusing to write empty script at $path" >&2
  exit 2
fi

chmod "$mode" "$path"
echo "wrote $path (mode $mode, $(wc -c < "$path") bytes)"
