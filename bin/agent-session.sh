#!/bin/sh
# agent-session.sh — wrapper invoked by launchd to manage a persistent
# tmux session for one agent.
#
# Usage: agent-session.sh <agent-name>
#   agent-name = directory name under WORKSPACE_ROOT/ AND tmux session name
#
# Behavior:
#   - Uses a per-agent tmux server socket (-L "$AGENT") so each agent gets
#     its own server process with its own environment. A single shared tmux
#     server would inherit the env of whichever launchd job booted it first,
#     leaking that agent's env vars into all the others.
#   - Creates the tmux session if it doesn't exist, with `claude --channels`
#     running inside
#   - Foreground-waits while the session lives (so launchd can monitor it)
#   - Exits when the session dies (claude /exit, crash, manual kill).
#     launchd KeepAlive will trigger a fresh start within ~10s.
#
# Environment:
#   WORKSPACE_ROOT — root containing all agent dirs
#                    (default: parent of this script's parent dir)
#   CLAUDE_BIN     — path to claude binary (default: discovered via PATH)
#   TMUX_BIN       — path to tmux (default: discovered via PATH)
#   CHANNELS_PLUGIN — plugin spec for claude --channels
#                     (default: plugin:telegram@claude-plugins-official)

set -eu

AGENT=${1:?usage: agent-session.sh <agent-name>}

# Resolve WORKSPACE_ROOT
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
WORKSPACE_ROOT="${WORKSPACE_ROOT:-$(dirname "$(dirname "$SCRIPT_DIR")")}"

DIR="${WORKSPACE_ROOT}/${AGENT}"
SESSION="${AGENT}"

CLAUDE="${CLAUDE_BIN:-$(command -v claude || true)}"
TMUX="${TMUX_BIN:-$(command -v tmux || true)}"
CHANNELS_PLUGIN="${CHANNELS_PLUGIN:-plugin:telegram@claude-plugins-official}"

[ -d "$DIR" ] || { echo "agent dir not found: $DIR" >&2; exit 1; }
[ -x "$CLAUDE" ] || { echo "claude binary not found (set CLAUDE_BIN env var)" >&2; exit 1; }
[ -x "$TMUX" ] || { echo "tmux binary not found (brew install tmux, or set TMUX_BIN)" >&2; exit 1; }

# Create the tmux session if absent
if ! "$TMUX" -L "$AGENT" has-session -t "$SESSION" 2>/dev/null; then
    "$TMUX" -L "$AGENT" new-session -d -s "$SESSION" -c "$DIR" \
        "exec $CLAUDE --dangerously-skip-permissions --channels $CHANNELS_PLUGIN"
fi

# Block while the session lives so launchd can supervise
while "$TMUX" -L "$AGENT" has-session -t "$SESSION" 2>/dev/null; do
    sleep 5
done
