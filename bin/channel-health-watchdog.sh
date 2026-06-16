#!/bin/bash
# channel-health-watchdog.sh — keep per-agent messaging channels healthy.
#
# Reference implementation. The messaging channel runs a poller process bound to
# the agent's session as MCP tools. A poller crash-loop (e.g. a stale poller
# contends for the platform's single-poller-per-bot slot during a respawn race)
# can drop the session's tool binding — and the framework does NOT auto-reconnect
# it (outbound via a direct-API script survives; inbound goes dark). See
# docs/channels-setup.md.
#
# This watchdog runs as one cheap pass (every ~2 min via the supervisor) across
# ALL agents — not one job per agent. Two jobs:
#   1. REAP duplicate pollers (keep the one under the live session).
#   2. DETECT active crash-loop churn and RECOVER — restart specialists
#      (debounced; context is persisted), alert-only for the orchestrator
#      (never restart it mid-conversation).
#
# Caveat: catches ACTIVE/recent churn. A long-settled-but-still-dark binding
# needs a per-agent inbound heartbeat (a v2 upgrade) — emit a timestamp on each
# inbound and flag staleness here.
#
# Config (override via env): AGENTS_DIR, ORCHESTRATOR, RESCUE_CMD, NOTIFY_CMD,
# POLLER_MATCH (pgrep pattern for the channel poller), ERRLOG_GLOB.
set -u
AGENTS_DIR="${AGENTS_DIR:-$HOME/agents}"
ORCHESTRATOR="${ORCHESTRATOR:-orchestrator}"   # alert-only; never auto-restarted
RESCUE_CMD="${RESCUE_CMD:-$AGENTS_DIR/shared/rescue.sh}"   # kills the agent's tmux; supervisor respawns
NOTIFY_CMD="${NOTIFY_CMD:-true}"               # outbound that bypasses the channel plugin
POLLER_MATCH="${POLLER_MATCH:-channel/.*/server.ts}"
ERRLOG_GLOB="${ERRLOG_GLOB:-$AGENTS_DIR/*/.channel/plugin.err}"
DEBOUNCE_MIN="${DEBOUNCE_MIN:-20}"
CHURN_WINDOW_SEC="${CHURN_WINDOW_SEC:-240}"
CHURN_PATTERN="${CHURN_PATTERN:-replacing stale poller\|shutting down}"
STATE_DIR="${STATE_DIR:-/tmp/channel-watchdog}"; mkdir -p "$STATE_DIR"
LOG="$STATE_DIR/watchdog.log"
DRYRUN="${WATCHDOG_DRYRUN:-0}"
now=$(date +%s)
log(){ echo "[$(date '+%F %T')] $*" >> "$LOG"; [ "$DRYRUN" = 1 ] && echo "$*"; }
do_kill(){ [ "$DRYRUN" = 1 ] && { log "  [dry-run] WOULD kill pid=$1"; return; }; kill -TERM "$1" 2>/dev/null; }
do_rescue(){ [ "$DRYRUN" = 1 ] && { log "  [dry-run] WOULD restart $1"; return 1; }; RESCUE_CALLER=watchdog sh "$RESCUE_CMD" "$1" 2>/dev/null; }
do_notify(){ [ "$DRYRUN" = 1 ] && { log "  [dry-run] WOULD notify: $1"; return; }; "$NOTIFY_CMD" "$1" 2>/dev/null; }

# which agent owns a pid (walk up to its tmux session label)
owner_label(){ local cur=$1 hops=0 cmd
  while [ -n "$cur" ] && [ "$cur" != 1 ] && [ $hops -lt 14 ]; do
    cmd=$(ps -o command= -p "$cur" 2>/dev/null)
    case "$cmd" in *"tmux -L "*) echo "$cmd" | sed -n 's/.*tmux -L \([a-zA-Z0-9_-]*\).*/\1/p'; return;; esac
    cur=$(ps -o ppid= -p "$cur" 2>/dev/null | tr -d ' '); hops=$((hops+1))
  done; }

POLLERS=$(for pid in $(pgrep -f "$POLLER_MATCH" 2>/dev/null); do
  ppid=$(ps -o ppid= -p "$pid" 2>/dev/null | tr -d ' ')
  lbl=$(owner_label "$ppid"); [ -z "$lbl" ] && lbl="ORPHAN"
  echo "$lbl $pid $ppid"
done)

# 1. reap duplicates (keep the poller whose parent is alive)
for agent in $(echo "$POLLERS" | awk 'NF{print $1}' | sort | uniq -d); do
  rows=$(echo "$POLLERS" | awk -v a="$agent" '$1==a')
  log "DUP: agent=$agent has $(echo "$rows" | grep -c .) pollers -> reaping stale"
  keep=""
  while read -r lbl pid ppid; do [ -z "$pid" ] && continue
    st=$(ps -o stat= -p "$ppid" 2>/dev/null | head -c1); case "$st" in S|R) keep=$pid; break;; esac
  done <<< "$rows"
  while read -r lbl pid ppid; do [ -z "$pid" ] && continue
    [ "$pid" = "$keep" ] && continue
    do_kill "$pid"; log "  reaped stale poller pid=$pid (kept $keep)"
  done <<< "$rows"
done

# 2. detect active crash-loop churn + recover
for errlog in $ERRLOG_GLOB; do
  [ -f "$errlog" ] || continue
  agent=$(echo "$errlog" | sed -n "s#${AGENTS_DIR}/\([^/]*\)/.*#\1#p")
  mtime=$(stat -f %m "$errlog" 2>/dev/null || stat -c %Y "$errlog" 2>/dev/null)
  age=$(( now - ${mtime:-0} )); [ "$age" -gt "$CHURN_WINDOW_SEC" ] && continue
  churn=$(tail -20 "$errlog" 2>/dev/null | grep -c "$CHURN_PATTERN")
  [ "$churn" -lt 3 ] && continue
  log "CHURN: agent=$agent active crash-loop (errlog age=${age}s, lines=$churn)"
  if [ "$agent" = "$ORCHESTRATOR" ]; then
    do_notify "watchdog: $agent channel is crash-looping (binding may be dark). Reconnect (/mcp) or restart — not auto-restarting the orchestrator mid-conversation."
    log "  orchestrator -> alert only"
  else
    last=$(cat "$STATE_DIR/last-restart-$agent" 2>/dev/null || echo 0)
    if [ $(( now - last )) -lt $(( DEBOUNCE_MIN*60 )) ]; then log "  $agent debounced -> skip"; else
      echo "$now" > "$STATE_DIR/last-restart-$agent"
      do_rescue "$agent" && log "  RESTARTED $agent"
      do_notify "watchdog: restarted $agent — its channel was crash-looping (binding dark). Context persisted; clean respawn shortly."
    fi
  fi
done
exit 0
