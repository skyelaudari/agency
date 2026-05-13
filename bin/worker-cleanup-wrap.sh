#!/bin/bash
# worker-cleanup-wrap.sh — wrap a delegation worker so that any process
# matching a configured pattern is killed when the worker exits.
#
# The common use case is a Chrome/Playwright instance using a shared
# user-data-dir that should release its single-process lock when this worker
# finishes — without this wrapper, an orphan Chrome can hold the lock for
# hours after the worker dies, blocking every other agent that wants the
# profile until someone manually pkill's it.
#
# Configuration via env var:
#
#   CLEANUP_PROCESS_PATTERNS — semicolon-separated list of `pgrep -f`
#                              patterns. Any matching process is killed on
#                              worker exit. Empty or unset = wrapper is a
#                              passthrough no-op.
#
# Example pattern (kills any Chrome using a specific shared profile):
#
#   export CLEANUP_PROCESS_PATTERNS='user-data-dir=/path/to/shared/playwright/user-data'
#
# Limitations:
#
# - SIGKILL on the worker bypasses the trap. Use a janitor cron as
#   belt-and-suspenders if you can't tolerate any orphan leakage.
# - This wrapper does NOT help with long-running agents that idle a browser
#   between active windows — that's a separate concern, addressed at the
#   browser-MCP layer (idle-timeout) or via the janitor cron.
# - The wrapper kills by process pattern, not by parent-PID. If two workers
#   somehow share a Chrome instance (shouldn't be possible given the
#   single-process lock, but conceivable in non-Chrome cases), this wrapper
#   would kill it for both. Use specific patterns to avoid collateral.
#
# Usage (from submit-delegation.sh):
#
#   worker-cleanup-wrap.sh /path/to/claude -p "<prompt>" --add-dir <dir> ...
#
# The first arg is the program to exec; subsequent args are passed through.

set -uo pipefail

PATTERNS="${CLEANUP_PROCESS_PATTERNS:-}"

cleanup() {
    [ -z "$PATTERNS" ] && return
    # Split on ; and run pkill -f on each pattern.
    IFS=';' read -ra PATS <<< "$PATTERNS"
    for p in "${PATS[@]}"; do
        [ -z "$p" ] && continue
        pkill -f "$p" 2>/dev/null || true
    done
    # Give processes a beat to flush, then escalate for stragglers
    # (Chrome typically spawns helpers like chrome_crashpad_handler that
    # should die with the parent).
    sleep 1
    for p in "${PATS[@]}"; do
        [ -z "$p" ] && continue
        pkill -9 -f "$p" 2>/dev/null || true
    done
}

trap cleanup EXIT INT TERM HUP

# exec replaces this bash and discards the trap. Run the target in the
# foreground + wait so the trap survives to fire on the child's exit.
"$@" &
CHILD_PID=$!

# Forward signals to the child; cleanup will also fire via trap.
trap 'kill -TERM "$CHILD_PID" 2>/dev/null; cleanup' INT TERM HUP

wait "$CHILD_PID"
EXIT_CODE=$?

# Cleanup once more on normal-exit path (the EXIT trap covers this, but
# explicit second call is cheap and defends against shell-impl quirks).
cleanup

exit "$EXIT_CODE"
