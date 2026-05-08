#!/bin/bash
# bootstrap-agent.sh — set up a new agent in the workspace.
#
# Creates the agent directory, scaffolds CLAUDE.md from template, sets up
# memory/ + cron/ + .mcp/ + logs/, generates the launchd session plist,
# and (optionally) bootstraps the launchd session.
#
# Usage:
#   bootstrap-agent.sh <agent-name> [--start]
#
# Args:
#   <agent-name>  — directory name AND tmux session name (lowercase, no spaces)
#   --start       — after bootstrap, immediately bootstrap the launchd session
#                   (you can defer this and run launchctl bootstrap manually)
#
# Environment:
#   WORKSPACE_ROOT — root containing all agent dirs (default: parent of this script's parent)
#   LABEL_PREFIX   — launchd label prefix for the session plist (default: com.agency)
#   USER_FIRST_NAME — substituted into CLAUDE.md template (default: "you")
#
# After this script:
#   1. Edit the new agent's CLAUDE.md to customize identity + boundaries
#   2. Set up the agent's Telegram bot (see docs/channels-setup.md)
#   3. Drop scoped OAuth tokens in <agent>/.mcp/oauth/ as needed
#   4. If you used --start, the agent is already running. Otherwise:
#        launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/<label>.plist

set -euo pipefail

usage() {
    echo "Usage: $0 <agent-name> [--start]" >&2
    exit 1
}

[ "$#" -ge 1 ] || usage

AGENT="$1"
shift

START_NOW=0
if [ "${1:-}" = "--start" ]; then
    START_NOW=1
fi

# Validate agent name (lowercase, no spaces, no slashes)
if ! echo "$AGENT" | grep -qE '^[a-z][a-z0-9-]*$'; then
    echo "error: agent name must be lowercase alphanumeric/hyphen, starting with a letter" >&2
    exit 1
fi

# Resolve paths
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
AGENCY_ROOT="$(dirname "$SCRIPT_DIR")"  # the agency repo dir
WORKSPACE_ROOT="${WORKSPACE_ROOT:-$(dirname "$AGENCY_ROOT")}"  # parent of agency/

LABEL_PREFIX="${LABEL_PREFIX:-com.agency}"
USER_FIRST_NAME="${USER_FIRST_NAME:-you}"

AGENT_DIR="${WORKSPACE_ROOT}/${AGENT}"

if [ -e "$AGENT_DIR" ]; then
    echo "error: agent dir already exists: $AGENT_DIR" >&2
    exit 1
fi

# Resolve binaries
CLAUDE_BIN="${CLAUDE_BIN:-$(command -v claude || true)}"
[ -x "$CLAUDE_BIN" ] || { echo "error: claude binary not found (set CLAUDE_BIN)" >&2; exit 1; }
CLAUDE_BIN_DIR=$(dirname "$CLAUDE_BIN")

TMUX_BIN="${TMUX_BIN:-$(command -v tmux || true)}"
[ -x "$TMUX_BIN" ] || { echo "error: tmux not found (brew install tmux, or set TMUX_BIN)" >&2; exit 1; }

echo "Creating agent: $AGENT"
echo "  agent dir:      $AGENT_DIR"
echo "  workspace root: $WORKSPACE_ROOT"
echo "  agency root:    $AGENCY_ROOT"
echo

# 1. Scaffold the agent directory tree
mkdir -p "$AGENT_DIR"/{memory,cron,.mcp/oauth,.claude/channels/telegram,logs}
chmod 700 "$AGENT_DIR/.mcp" "$AGENT_DIR/.mcp/oauth"

# 2. Copy CLAUDE.md from template, with substitutions
TEMPLATE="${AGENCY_ROOT}/templates/agent/CLAUDE.md.template"
[ -r "$TEMPLATE" ] || { echo "error: template not found: $TEMPLATE" >&2; exit 1; }

sed \
    -e "s|{{AGENT_NAME}}|${AGENT}|g" \
    -e "s|{{USER_FIRST_NAME}}|${USER_FIRST_NAME}|g" \
    -e "s|{{WORKSPACE_ROOT}}|${WORKSPACE_ROOT}|g" \
    "$TEMPLATE" > "$AGENT_DIR/CLAUDE.md"

echo "  ✓ CLAUDE.md scaffolded (edit to customize identity + boundaries)"

# 3. Initial MEMORY.md
cat > "$AGENT_DIR/MEMORY.md" <<EOF
# MEMORY.md — ${AGENT}

Curated cross-session memory. Append-only journal of durable learnings.

(Empty on bootstrap. Will fill as feedback + learnings accumulate.)
EOF
echo "  ✓ MEMORY.md initialized"

# 4. Initial daily log
TODAY=$(date +%Y-%m-%d)
cat > "$AGENT_DIR/memory/${TODAY}.md" <<EOF
# ${TODAY}

Bootstrapped today via agency/bin/bootstrap-agent.sh.
EOF
echo "  ✓ memory/${TODAY}.md initialized"

# 5. Generate the session plist from template
SESSION_LABEL="${LABEL_PREFIX}.${AGENT}.session"
PLIST_TEMPLATE="${AGENCY_ROOT}/plists/agent-session.plist.template"
PLIST_OUT="${HOME}/Library/LaunchAgents/${SESSION_LABEL}.plist"

[ -r "$PLIST_TEMPLATE" ] || { echo "error: plist template not found: $PLIST_TEMPLATE" >&2; exit 1; }

mkdir -p "${HOME}/Library/LaunchAgents"

sed \
    -e "s|{{LABEL}}|${SESSION_LABEL}|g" \
    -e "s|{{AGENT_NAME}}|${AGENT}|g" \
    -e "s|{{WORKSPACE_ROOT}}|${WORKSPACE_ROOT}|g" \
    -e "s|{{HOME}}|${HOME}|g" \
    -e "s|{{CLAUDE_BIN_DIR}}|${CLAUDE_BIN_DIR}|g" \
    "$PLIST_TEMPLATE" > "$PLIST_OUT"

# The template references the agency-shipped agent-session.sh at
# {{WORKSPACE_ROOT}}/.agency/bin/agent-session.sh — but the agency repo
# is wherever the user cloned it. Fix the path to match this install.
# (Substitute the placeholder with the actual agency root.)
AGENCY_BIN_PATH="${AGENCY_ROOT}/bin/agent-session.sh"
sed -i.bak \
    -e "s|${WORKSPACE_ROOT}/.agency/bin/agent-session.sh|${AGENCY_BIN_PATH}|g" \
    "$PLIST_OUT"
rm -f "${PLIST_OUT}.bak"

# Validate the plist
if ! plutil -lint "$PLIST_OUT" >/dev/null 2>&1; then
    echo "error: generated plist is invalid:" >&2
    plutil -lint "$PLIST_OUT" >&2
    exit 1
fi

echo "  ✓ launchd plist written: $PLIST_OUT"
echo "    (label: $SESSION_LABEL)"

# 6. Optionally bootstrap the launchd session
if [ "$START_NOW" -eq 1 ]; then
    echo
    echo "Starting launchd session..."
    if launchctl bootstrap "gui/$(id -u)" "$PLIST_OUT" 2>&1; then
        echo "  ✓ session running. Tail logs:"
        echo "      tail -f $AGENT_DIR/logs/session.out"
        echo "      tail -f $AGENT_DIR/logs/session.err"
    else
        echo "  ! launchctl bootstrap failed; bootstrap manually:" >&2
        echo "      launchctl bootstrap gui/$(id -u) $PLIST_OUT" >&2
    fi
else
    echo
    echo "To start the session:"
    echo "  launchctl bootstrap gui/\$(id -u) $PLIST_OUT"
fi

echo
echo "Next steps:"
echo "  1. Edit $AGENT_DIR/CLAUDE.md — customize identity, role, voice, hard boundaries"
echo "  2. (Optional) Set up a Telegram bot for this agent — see agency/docs/channels-setup.md"
echo "  3. (Optional) Add scoped OAuth tokens at $AGENT_DIR/.mcp/oauth/<service>.json (mode 600)"
echo "  4. Connect via tmux to inspect or interact:"
echo "       tmux -L $AGENT attach -t $AGENT"
