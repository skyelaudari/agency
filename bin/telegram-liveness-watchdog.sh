#!/bin/bash
# telegram-liveness-watchdog.sh — detects an agent whose Telegram plugin process
# has died, and restarts that agent's session ONLY after it has checkpointed.
#
# WHY: the channel plugin can die silently, with no crash loop and nothing in its
# error log. Claude Code does not respawn a dead plugin MCP, so inbound messages
# vanish until someone runs /mcp in that terminal. channel-health-watchdog.sh
# only detects crash-loop churn in the plugin's error log, not a quiet death.
#
# DETECTION: every agent's tmux pane runs claude directly (agent-session.sh uses
# `exec claude`), and the telegram plugin runs as a direct child of that claude
# process. No plugin child on MISS_THRESHOLD consecutive checks = dead binding.
#
# RECOVERY RULE: never restart without a checkpoint, so current work is never lost.
#   1. Wait until the agent is not mid-turn (the orchestrator also needs several
#      consecutive idle checks).
#   2. Type a checkpoint instruction into its terminal.
#   3. Restart only once memory/checkpoint.md has been rewritten after the request.
#      No confirmed checkpoint = no restart: alert and leave it alone.
#   4. Kill the tmux session; launchd KeepAlive respawns it, and agent-session.sh's
#      boot kick has the fresh session read the checkpoint.
# At most one auto-restart per agent per DEBOUNCE_SEC; a repeat inside that
# window alerts instead of looping.
#
# Run every 120s via launchd (plists/telegram-liveness.plist.template). It runs
# outside every agent session, so killing a session does not interrupt it.
# See docs/session-continuity.md.
#
# Configuration (env):
#   WORKSPACE_ROOT  root containing all agent dirs (required)
#   AGENTS          space-separated agent names = tmux socket/session names (required)
#   ORCHESTRATOR    agent that needs ORCH_IDLE_CHECKS idle checks before restart
#   NOTIFY_CMD      command that sends an alert; called as: $NOTIFY_CMD "<message>"
#                   (optional; without it, alerts only go to the log)
#   PLUGIN_PATTERN  pgrep -f pattern for the plugin process
#                   (default: claude-plugins-official/telegram)
#   TMUX_BIN        path to tmux (default: discovered via PATH)
#   DRYRUN=1        log decisions without sending keys, killing, or notifying
#   FORCE_DEAD=<agent>  simulate a dead binding for that agent (use with DRYRUN=1)

set -u
WORKSPACE_ROOT="${WORKSPACE_ROOT:?set WORKSPACE_ROOT}"
AGENTS="${AGENTS:?set AGENTS (space-separated agent names)}"
ORCHESTRATOR="${ORCHESTRATOR:-}"
NOTIFY_CMD="${NOTIFY_CMD:-}"
PLUGIN_PATTERN="${PLUGIN_PATTERN:-claude-plugins-official/telegram}"
TMUX="${TMUX_BIN:-$(command -v tmux)}"
STATE_DIR="${STATE_DIR:-$HOME/.local/state/telegram-liveness}"; mkdir -p "$STATE_DIR"
LOG="${LOG:-$STATE_DIR/watchdog.log}"
MISS_THRESHOLD=2            # consecutive dead checks before acting
ORCH_IDLE_CHECKS=3          # consecutive idle checks the orchestrator needs (~6 min)
CHECKPOINT_TIMEOUT=240      # seconds to wait for checkpoint.md to be rewritten
DEBOUNCE_SEC=1800
BOOT_GRACE_SEC=180          # ignore sessions younger than this (plugins still starting)
DRYRUN="${DRYRUN:-0}"
FORCE_DEAD="${FORCE_DEAD:-}"
now=$(date +%s)

log(){ echo "[$(date '+%F %T')] $*" >> "$LOG"; [ "$DRYRUN" = 1 ] && echo "[$(date '+%F %T')] $*"; }
notify(){
  [ "$DRYRUN" = 1 ] && { log "  [dry-run] WOULD notify: $1"; return; }
  [ -n "$NOTIFY_CMD" ] && $NOTIFY_CMD "$1" >/dev/null 2>&1
  log "notify: $1"
}
getst(){ cat "$STATE_DIR/$1" 2>/dev/null || echo "${2:-0}"; }
setst(){ echo "$2" > "$STATE_DIR/$1"; }

# "esc to interrupt" is shown in the claude TUI while a turn is running
busy(){ "$TMUX" -L "$1" capture-pane -p -t "$1" 2>/dev/null | grep -qi "esc to interrupt"; }

CHECKPOINT_MSG="SYSTEM (telegram-liveness watchdog): your Telegram connection has died. This session will be restarted to restore it as soon as you have checkpointed. Do NOT try to reply on Telegram, the channel is down. Right now, overwrite memory/checkpoint.md (relative to your working directory) with: the current timestamp, what you were working on, who with and about what, anything unresolved, and the next step. If you were mid-conversation on Telegram, add a line 'Restart notice sent: telegram' so your fresh session sends a back-online message. Write the file even if there is nothing in flight (say so). Do not do anything else."

for agent in $AGENTS; do
  "$TMUX" -L "$agent" has-session -t "$agent" 2>/dev/null || continue
  pane=$("$TMUX" -L "$agent" list-panes -t "$agent" -F '#{pane_pid}' 2>/dev/null | head -1)
  [ -z "$pane" ] && continue

  # skip sessions still booting (macOS date syntax)
  started=$(ps -o lstart= -p "$pane" 2>/dev/null)
  [ -n "$started" ] && age=$(( now - $(date -j -f "%a %b %d %T %Y" "$started" +%s 2>/dev/null || echo "$now") )) || age=0
  [ "$age" -lt "$BOOT_GRACE_SEC" ] && { setst "miss-$agent" 0; continue; }

  tg=$(pgrep -P "$pane" -f "$PLUGIN_PATTERN" 2>/dev/null | head -1)
  [ "$FORCE_DEAD" = "$agent" ] && tg=""
  if [ -n "$tg" ]; then
    [ "$(getst "miss-$agent")" != 0 ] && log "$agent: telegram alive again (pid $tg)"
    setst "miss-$agent" 0; setst "idle-$agent" 0; setst "alerted-$agent" 0
    continue
  fi

  miss=$(( $(getst "miss-$agent") + 1 )); setst "miss-$agent" "$miss"
  log "$agent: no telegram process (miss $miss/$MISS_THRESHOLD)"
  [ "$miss" -lt "$MISS_THRESHOLD" ] && continue

  # debounce: a second death inside the window means something is wrong, don't loop
  last=$(getst "restart-$agent")
  if [ $(( now - last )) -lt "$DEBOUNCE_SEC" ]; then
    if [ "$(getst "alerted-$agent")" = 0 ]; then
      notify "⚠️ watchdog: $agent's Telegram died again soon after an auto-restart. Not restarting again. It needs a look (run /mcp in its terminal)."
      setst "alerted-$agent" 1
    fi
    log "$agent: inside debounce window, alert only"
    continue
  fi

  # wait for the agent to be idle before interrupting it
  if busy "$agent"; then
    setst "idle-$agent" 0; log "$agent: mid-turn, waiting"; continue
  fi
  idle=$(( $(getst "idle-$agent") + 1 )); setst "idle-$agent" "$idle"
  if [ "$agent" = "$ORCHESTRATOR" ] && [ "$idle" -lt "$ORCH_IDLE_CHECKS" ]; then
    log "$agent: idle check $idle/$ORCH_IDLE_CHECKS before restart"; continue
  fi

  # checkpoint first, then restart only on a confirmed write
  cp="$WORKSPACE_ROOT/$agent/memory/checkpoint.md"
  mkdir -p "$WORKSPACE_ROOT/$agent/memory"
  before=$(stat -f %m "$cp" 2>/dev/null || echo 0)
  asked=$(date +%s)
  log "$agent: requesting checkpoint before restart"
  if [ "$DRYRUN" = 1 ]; then
    log "  [dry-run] WOULD send checkpoint instruction, wait up to ${CHECKPOINT_TIMEOUT}s for $cp, then kill tmux session"
    continue
  fi
  "$TMUX" -L "$agent" send-keys -t "$agent" -l "$CHECKPOINT_MSG" 2>/dev/null
  "$TMUX" -L "$agent" send-keys -t "$agent" C-m 2>/dev/null

  ok=0; waited=0
  while [ "$waited" -lt "$CHECKPOINT_TIMEOUT" ]; do
    sleep 10; waited=$((waited + 10))
    m=$(stat -f %m "$cp" 2>/dev/null || echo 0)
    if [ "$m" -gt "$before" ] && [ "$m" -ge "$asked" ] && [ -s "$cp" ] && ! busy "$agent"; then ok=1; break; fi
  done

  if [ "$ok" != 1 ]; then
    log "$agent: checkpoint NOT confirmed after ${waited}s, not restarting"
    notify "⚠️ watchdog: $agent's Telegram is down, but it didn't confirm a checkpoint, so it was NOT restarted (rule: checkpoint before any restart). Run /mcp in its terminal, or restart it by hand."
    setst "restart-$agent" "$now"; setst "alerted-$agent" 1
    continue
  fi

  log "$agent: checkpoint written ($(wc -c < "$cp" | tr -d ' ') bytes), restarting session"
  "$TMUX" -L "$agent" kill-session -t "$agent" 2>/dev/null
  setst "restart-$agent" "$(date +%s)"; setst "miss-$agent" 0; setst "idle-$agent" 0
  notify "🔧 watchdog: $agent's Telegram connection had died. It checkpointed and its session was restarted. Back in ~15s with Telegram reconnected."
done
exit 0
