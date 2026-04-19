#!/usr/bin/env bash
# Long-running background worker manager. Wraps systemd-run so Tai can
# launch processes that outlive the current conversation, follow their
# logs, and stop them cleanly. Unit names are prefixed with
# "workspace-worker-" to keep them discoverable.
#
# Subcommands:
#   start <name> "<command>"  # launch a transient systemd unit
#   list                       # list known workspace workers
#   log <name> [--follow]      # show worker's journal
#   stop <name>                # stop the unit (it auto-cleans up)
#   status <name>              # systemctl status
#
# Examples:
#   scripts/worker.sh start long-reflect 'bash /root/.openclaw/workspace/scripts/reflect.sh'
#   scripts/worker.sh list
#   scripts/worker.sh log long-reflect
#   scripts/worker.sh stop long-reflect

set -uo pipefail

PREFIX="workspace-worker-"
CMD="${1:-}"
shift || true

case "$CMD" in
  start)
    NAME="${1:-}"
    shift || true
    RUN="${*:-}"
    if [ -z "$NAME" ] || [ -z "$RUN" ]; then
      echo "Usage: $(basename "$0") start <name> \"<command>\"" >&2; exit 2
    fi
    UNIT="${PREFIX}${NAME}"
    # systemd-run needs absolute paths; we pass via bash -c
    systemd-run --unit="$UNIT" --collect \
      --property=StandardOutput=journal \
      --property=StandardError=journal \
      /bin/bash -c "$RUN"
    echo "Started $UNIT"
    echo "Tail logs:  $(basename "$0") log $NAME"
    echo "Stop:       $(basename "$0") stop $NAME"
    ;;

  list)
    # All workspace workers (active and inactive)
    systemctl list-units --all --type=service "${PREFIX}*" --no-pager --no-legend 2>/dev/null \
      | awk 'BEGIN {printf "%-35s %-10s %-10s %s\n", "UNIT", "LOAD", "ACTIVE", "SUB"} {printf "%-35s %-10s %-10s %s\n", $1, $2, $3, $4}'
    ;;

  log)
    NAME="${1:-}"
    if [ -z "$NAME" ]; then echo "Usage: $(basename "$0") log <name> [--follow]" >&2; exit 2; fi
    shift || true
    UNIT="${PREFIX}${NAME}"
    if [ "${1:-}" = "--follow" ]; then
      journalctl -u "$UNIT" -f
    else
      journalctl -u "$UNIT" --no-pager -n 200
    fi
    ;;

  stop)
    NAME="${1:-}"
    if [ -z "$NAME" ]; then echo "Usage: $(basename "$0") stop <name>" >&2; exit 2; fi
    UNIT="${PREFIX}${NAME}"
    systemctl stop "$UNIT" 2>&1 || true
    echo "Stopped $UNIT"
    ;;

  status)
    NAME="${1:-}"
    if [ -z "$NAME" ]; then echo "Usage: $(basename "$0") status <name>" >&2; exit 2; fi
    UNIT="${PREFIX}${NAME}"
    systemctl status "$UNIT" --no-pager -n 20 || true
    ;;

  *)
    echo "Usage: $(basename "$0") {start|list|log|stop|status} ..." >&2
    echo "Example: $(basename "$0") start my-task 'sleep 3600 && echo done'" >&2
    exit 2
    ;;
esac
