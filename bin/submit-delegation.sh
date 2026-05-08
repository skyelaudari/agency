#!/bin/bash
# submit-delegation.sh — file a Claude delegation as a launchd one-shot job.
#
# WHY launchd (not subshell): subshell-spawned children inherit the parent's
# process group at the kernel level. Some MCP server transports (notably the
# Telegram channels-mode plugin running under bun) interpret the spawn-time
# process tree perturbation as transport-unhealthy and recycle, killing the
# parent's MCP-to-claude pipe. Routing through launchd makes the child a
# direct PID-1 descendant in its own session — fully decoupled.
#
# Usage:
#   submit-delegation.sh <target_agent> <prompt_file> [--add-dir <dir>] \
#                                                    [--mcp-config <path>] \
#                                                    [--strict-mcp-config] \
#                                                    [--allowed-tools "<list>"]
#
# Args:
#   <target_agent>     — agent directory name under WORKSPACE_ROOT
#                        (e.g., "researcher" → $WORKSPACE_ROOT/researcher/)
#   <prompt_file>      — path to a file containing the wake-prompt text
#   --add-dir <dir>    — additional directory the spawned session can access
#   --mcp-config <p>   — explicit .mcp.json path (otherwise inherits target's)
#   --strict-mcp-config — pair with --mcp-config to lock down MCP loading
#   --allowed-tools "<list>" — limit tool surface (space-separated)
#
# Environment:
#   WORKSPACE_ROOT — root containing all agent dirs (default: parent of this script's dir)
#   LABEL_PREFIX   — launchd job label prefix (default: "com.agency.delegation")
#   CLAUDE_BIN     — path to claude binary (default: discovered via `which claude`)
#
# Returns:
#   stdout: the unique job label (e.g., com.agency.delegation.researcher.20260507-142030-a3f7)
#   exit 0 on success, non-zero on failure

set -euo pipefail

usage() {
    cat >&2 <<EOF
Usage: $0 <target_agent> <prompt_file> [--add-dir <dir>] [--mcp-config <path>] [--strict-mcp-config] [--allowed-tools "<list>"]

Environment:
  WORKSPACE_ROOT  Root containing all agent directories
  LABEL_PREFIX    launchd job label prefix (default: com.agency.delegation)
  CLAUDE_BIN      Path to claude binary (default: discovered via PATH)
EOF
    exit 1
}

[ "$#" -ge 2 ] || usage

TARGET="$1"
PROMPT_FILE="$2"
shift 2

# Resolve WORKSPACE_ROOT: explicit env var, or two dirs up from this script
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
WORKSPACE_ROOT="${WORKSPACE_ROOT:-$(dirname "$(dirname "$SCRIPT_DIR")")}"

# Resolve CLAUDE_BIN
CLAUDE_BIN="${CLAUDE_BIN:-$(command -v claude || true)}"
[ -x "$CLAUDE_BIN" ] || { echo "error: claude binary not found (set CLAUDE_BIN env var)" >&2; exit 1; }

# Default label prefix
LABEL_PREFIX="${LABEL_PREFIX:-com.agency.delegation}"

# Verify target agent dir exists
TARGET_DIR="${WORKSPACE_ROOT}/${TARGET}"
[ -d "$TARGET_DIR" ] || { echo "error: agent dir not found: $TARGET_DIR" >&2; exit 1; }
[ -r "$PROMPT_FILE" ] || { echo "error: prompt file not readable: $PROMPT_FILE" >&2; exit 1; }

ADD_DIR=""
MCP_CONFIG=""
STRICT_MCP=0
ALLOWED_TOOLS=""

while [ "$#" -gt 0 ]; do
    case "$1" in
        --add-dir)           ADD_DIR="$2"; shift 2 ;;
        --mcp-config)        MCP_CONFIG="$2"; shift 2 ;;
        --strict-mcp-config) STRICT_MCP=1; shift ;;
        --allowed-tools)     ALLOWED_TOOLS="$2"; shift 2 ;;
        *) echo "unknown option: $1" >&2; usage ;;
    esac
done

# Generate unique label: prefix + target + timestamp + 4-char random suffix
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
RANDOM_SUFFIX=$(openssl rand -hex 2)
LABEL="${LABEL_PREFIX}.${TARGET}.${TIMESTAMP}-${RANDOM_SUFFIX}"

# Delegation state dir under workspace root
DELEG_DIR="${WORKSPACE_ROOT}/.delegations/${LABEL}"
mkdir -p "$DELEG_DIR"

PLIST_PATH="${DELEG_DIR}/job.plist"
LOG_OUT="${DELEG_DIR}/output.log"
LOG_ERR="${DELEG_DIR}/output.err"
PROMPT_COPY="${DELEG_DIR}/prompt.txt"

# Copy the prompt into the deleg dir (record + insulation from external file moves)
cp "$PROMPT_FILE" "$PROMPT_COPY"

# XML-escape function for plist string values
xml_escape() {
    sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g'
}

# Read prompt + escape
PROMPT_ESCAPED=$(xml_escape < "$PROMPT_COPY")
CLAUDE_BIN_ESCAPED=$(echo "$CLAUDE_BIN" | xml_escape)
TARGET_DIR_ESCAPED=$(echo "$TARGET_DIR" | xml_escape)

# Build the ProgramArguments array
ARGS_XML="        <string>${CLAUDE_BIN_ESCAPED}</string>
        <string>-p</string>
        <string>${PROMPT_ESCAPED}</string>"

if [ -n "$ADD_DIR" ]; then
    ADD_DIR_ESCAPED=$(echo "$ADD_DIR" | xml_escape)
    ARGS_XML="${ARGS_XML}
        <string>--add-dir</string>
        <string>${ADD_DIR_ESCAPED}</string>"
fi

if [ "$STRICT_MCP" -eq 1 ]; then
    ARGS_XML="${ARGS_XML}
        <string>--strict-mcp-config</string>"
fi

if [ -n "$MCP_CONFIG" ]; then
    MCP_CONFIG_ESCAPED=$(echo "$MCP_CONFIG" | xml_escape)
    ARGS_XML="${ARGS_XML}
        <string>--mcp-config</string>
        <string>${MCP_CONFIG_ESCAPED}</string>"
fi

if [ -n "$ALLOWED_TOOLS" ]; then
    ALLOWED_TOOLS_ESCAPED=$(echo "$ALLOWED_TOOLS" | xml_escape)
    ARGS_XML="${ARGS_XML}
        <string>--allowedTools</string>
        <string>${ALLOWED_TOOLS_ESCAPED}</string>"
fi

ARGS_XML="${ARGS_XML}
        <string>--dangerously-skip-permissions</string>"

# Construct PATH that includes the dir of CLAUDE_BIN (so spawned shells find it)
CLAUDE_BIN_DIR=$(dirname "$CLAUDE_BIN")
SPAWN_PATH="${CLAUDE_BIN_DIR}:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
SPAWN_PATH_ESCAPED=$(echo "$SPAWN_PATH" | xml_escape)
HOME_ESCAPED=$(echo "$HOME" | xml_escape)
LOG_OUT_ESCAPED=$(echo "$LOG_OUT" | xml_escape)
LOG_ERR_ESCAPED=$(echo "$LOG_ERR" | xml_escape)
LABEL_ESCAPED=$(echo "$LABEL" | xml_escape)

# Generate the plist
cat > "$PLIST_PATH" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>${LABEL_ESCAPED}</string>

    <key>ProgramArguments</key>
    <array>
${ARGS_XML}
    </array>

    <key>WorkingDirectory</key>
    <string>${TARGET_DIR_ESCAPED}</string>

    <key>EnvironmentVariables</key>
    <dict>
        <key>PATH</key>
        <string>${SPAWN_PATH_ESCAPED}</string>
        <key>HOME</key>
        <string>${HOME_ESCAPED}</string>
    </dict>

    <key>RunAtLoad</key>
    <true/>

    <key>KeepAlive</key>
    <false/>

    <key>StandardOutPath</key>
    <string>${LOG_OUT_ESCAPED}</string>

    <key>StandardErrorPath</key>
    <string>${LOG_ERR_ESCAPED}</string>
</dict>
</plist>
EOF

# Validate plist
if ! plutil -lint "$PLIST_PATH" >/dev/null 2>&1; then
    echo "error: generated plist is invalid XML" >&2
    plutil -lint "$PLIST_PATH" >&2
    exit 1
fi

# Bootstrap into launchd — this fires the job immediately due to RunAtLoad=true
if ! launchctl bootstrap "gui/$(id -u)" "$PLIST_PATH" 2>"${DELEG_DIR}/bootstrap.err"; then
    echo "error: launchctl bootstrap failed" >&2
    cat "${DELEG_DIR}/bootstrap.err" >&2
    exit 1
fi

# Return the label so caller can poll
echo "$LABEL"
