#!/bin/bash
# cleanup-delegation.sh — bootout a completed delegation job and optionally remove its artifacts.
#
# Usage:
#   cleanup-delegation.sh <label> [--keep-logs]
#
# Default: bootouts the launchd job + removes the entire deleg dir (plist + logs + prompt).
# With --keep-logs: bootouts but preserves output.log + output.err for review.
#
# Environment:
#   WORKSPACE_ROOT — root containing the .delegations/ state dir
#                    (default: parent of this script's dir)

set -euo pipefail

LABEL="${1:-}"
[ -n "$LABEL" ] || { echo "Usage: $0 <label> [--keep-logs]" >&2; exit 1; }
shift

KEEP_LOGS=0
if [ "${1:-}" = "--keep-logs" ]; then
    KEEP_LOGS=1
fi

# Resolve WORKSPACE_ROOT
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
WORKSPACE_ROOT="${WORKSPACE_ROOT:-$(dirname "$(dirname "$SCRIPT_DIR")")}"

DELEG_DIR="${WORKSPACE_ROOT}/.delegations/${LABEL}"
PLIST_PATH="${DELEG_DIR}/job.plist"

# Bootout (ignore errors — may already be cleared)
launchctl bootout "gui/$(id -u)/${LABEL}" 2>/dev/null || true

if [ "$KEEP_LOGS" -eq 1 ]; then
    # Just remove the plist; keep the deleg dir for review
    rm -f "$PLIST_PATH" "${DELEG_DIR}/bootstrap.err" "${DELEG_DIR}/prompt.txt"
    echo "kept logs at: $DELEG_DIR" >&2
else
    rm -rf "$DELEG_DIR"
fi
