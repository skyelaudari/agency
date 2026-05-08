#!/bin/bash
# wait-delegation.sh — block until a launchd-submitted delegation completes.
#
# Polls launchctl every 5s for the job's state. Returns when:
#   - Job exits cleanly (state goes from "running" to absent or "exit code")
#   - Timeout reached (defaults to 7200s = 2hr)
#
# Usage:
#   wait-delegation.sh <label> [--timeout <seconds>]
#
# Environment:
#   WORKSPACE_ROOT — root containing the .delegations/ state dir
#                    (default: parent of this script's dir)
#
# Returns:
#   stdout: log path (e.g., $WORKSPACE_ROOT/.delegations/<label>/output.log)
#   exit 0: job completed cleanly
#   exit 1: job exited non-zero
#   exit 2: timeout reached

set -euo pipefail

LABEL="${1:-}"
[ -n "$LABEL" ] || { echo "Usage: $0 <label> [--timeout <seconds>]" >&2; exit 1; }
shift

TIMEOUT=7200  # 2 hours default
POLL_INTERVAL=5

while [ "$#" -gt 0 ]; do
    case "$1" in
        --timeout) TIMEOUT="$2"; shift 2 ;;
        *) echo "unknown option: $1" >&2; exit 1 ;;
    esac
done

# Resolve WORKSPACE_ROOT: explicit env var, or two dirs up from this script
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
WORKSPACE_ROOT="${WORKSPACE_ROOT:-$(dirname "$(dirname "$SCRIPT_DIR")")}"

DELEG_DIR="${WORKSPACE_ROOT}/.delegations/${LABEL}"
LOG_OUT="${DELEG_DIR}/output.log"

[ -d "$DELEG_DIR" ] || { echo "error: deleg dir not found: $DELEG_DIR" >&2; exit 1; }

START=$(date +%s)
while true; do
    NOW=$(date +%s)
    ELAPSED=$((NOW - START))

    if [ "$ELAPSED" -ge "$TIMEOUT" ]; then
        echo "$LOG_OUT"
        echo "warning: timeout reached after ${TIMEOUT}s; job may still be running" >&2
        exit 2
    fi

    # Query launchctl print to see job state
    # States: "waiting", "running", or "not loaded" (job completed + cleaned up)
    STATE_OUTPUT=$(launchctl print "gui/$(id -u)/${LABEL}" 2>&1 || true)

    if echo "$STATE_OUTPUT" | grep -q "Could not find service"; then
        # Job no longer in launchd — completed and was naturally cleaned up
        echo "$LOG_OUT"
        exit 0
    fi

    # Job still in launchd. Check state.
    STATE_LINE=$(echo "$STATE_OUTPUT" | grep -E "^[[:space:]]*state =" | head -1 || true)

    if echo "$STATE_LINE" | grep -q "not running"; then
        # Job completed but still in launchd. Check last exit status.
        LAST_EXIT=$(echo "$STATE_OUTPUT" | grep -E "last exit code = " | head -1 | awk '{print $NF}')
        echo "$LOG_OUT"
        if [ "${LAST_EXIT:-0}" -eq 0 ]; then
            exit 0
        else
            echo "warning: job exited with code $LAST_EXIT" >&2
            exit 1
        fi
    fi

    sleep "$POLL_INTERVAL"
done
