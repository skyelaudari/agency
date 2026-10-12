# Session continuity

Memory (see `docs/memory-conventions.md`) solves one problem: durable knowledge (facts, decisions, lessons) surviving a restart. In-flight session state is a different problem. That means what the agent was doing, who it was talking to, and what was left unresolved when the session died. Memory doesn't cover it. A long-running agent gets restarted for many reasons: a contract edit that needs a reload, the weekly recycler, a dead channel. Without a handoff, every restart drops the thread mid-conversation.

This doc covers the mechanism that closes that gap. It has four parts: a checkpoint file, a boot trigger that reads it, a notice/back-online pair so the user knows what happened, and a watchdog that restarts a deaf agent only after it has checkpointed.

## 1. The checkpoint file

Path: `<agent>/memory/checkpoint.md`

A single snapshot that is **overwritten each time, never appended**. It isn't a log. It holds the current state or nothing.

Contents, kept short (a handoff note, not a transcript):
- timestamp
- what the agent was doing
- who with, and about what
- anything unresolved
- the next step, if there is one

**Write it before any restart the agent initiates itself**, in the same session and before the kill.

**On boot, read it, pick up the thread, then clear it.** Delete the file or blank it. A checkpoint that outlives the session it was written for will mislead a later boot. It's the same failure as a one-shot reminder that never cleans itself up.

## 2. The boot trigger

A rule in `CLAUDE.md` that says "read the checkpoint on boot" never fires by itself. A freshly started session sits idle at its prompt until a message arrives, so a test checkpoint can stay unread for hours. The boot trigger has to come from outside the session.

`bin/agent-session.sh` does this. After creating the tmux session, if `memory/checkpoint.md` is non-empty, it waits for the claude prompt to render and types an instruction: read the checkpoint, pick up the thread, send the back-online message if one is owed, clear the file. If no checkpoint exists, it does nothing, so agents without the convention are unaffected. A crash or rescue restart (no checkpoint) also stays silent.

## 3. Restart notice + back-online ping: always a pair

From the user's side, an agent that goes quiet mid-conversation looks broken. The fix is a pair of messages:

- **Before a deliberate restart:** the agent tells the user on the channel they're talking on ("Restarting now, I'll message when I'm back") and puts a line in the checkpoint: `Restart notice sent: telegram`.
- **On boot:** if that line is present, the first outbound message is "Back online" through the channel's **reply tool**. Don't use an out-of-band notify script for this. The reply tool working is the proof the channel binding is live. A script would only prove tmux respawned.

No notice sent means no back-online ping. Scheduled restarts during quiet hours stay silent unless the agent was mid-conversation.

## 4. Everything that restarts a session goes through the checkpoint

There are three paths, and all of them write to the same file:

| Restart path | Who writes the checkpoint |
|---|---|
| Agent-initiated (e.g. after editing its own `CLAUDE.md`) | The agent, in the same turn, before killing its session |
| Periodic recycler (see `docs/identity-contracts.md`, "Config is read once") | The recycler types a checkpoint-and-wait instruction into the live session, then waits for the file before killing it |
| Channel liveness watchdog (below) | Same as the recycler: request, confirm the write, then restart |

Point all three at `memory/checkpoint.md`, not at "write it down somewhere." One file is what the boot trigger knows to look for.

## 5. The liveness watchdog: restart a deaf agent, but only after a checkpoint

`bin/telegram-liveness-watchdog.sh` (launchd template: `plists/telegram-liveness.plist.template`).

**The failure it catches.** The channel plugin process can die quietly, with no crash loop and nothing in its error log. Claude Code doesn't respawn a dead plugin MCP, so inbound messages vanish until someone runs `/mcp` in that terminal. The earlier `channel-health-watchdog.sh` caught crash-loop churn in the plugin's error log. It didn't catch this.

**Detection.** Each agent's tmux pane runs `claude` directly (`exec claude` in `agent-session.sh`), and the channel plugin runs as a direct child of that process. If no plugin child appears on 2 consecutive checks (~4 minutes at a 2-minute interval), the binding is dead. Sessions younger than a few minutes are skipped while plugins start.

**Recovery: never restart without a checkpoint.**
1. Wait until the agent isn't mid-turn. The orchestrator also needs several consecutive idle checks, since it's the one most likely to be in a conversation.
2. Type a checkpoint instruction into its terminal. It tells the agent its channel is down, not to try replying on it, and to write `memory/checkpoint.md`, including the restart-notice line if it was mid-conversation.
3. Restart only once the checkpoint file has been rewritten after the request. **No confirmed checkpoint means no restart.** Alert the user and leave the session alone.
4. Kill the tmux session. launchd `KeepAlive` respawns it, and the boot trigger has the fresh session read the checkpoint and send the back-online ping.

At most one auto-restart per agent per 30 minutes. A second death inside that window sends an alert and doesn't restart again, so a persistent fault can't cause a restart loop.

`DRYRUN=1` logs decisions without sending keys, killing, or notifying. `FORCE_DEAD=<agent>` simulates a dead binding for testing.

## What this doesn't cover

A hung session killed by the rescue protocol, or a hard crash, gives no warning and can't checkpoint itself. That's an accepted, documented gap. The mechanism covers the common cases (scheduled recycler, deliberate restart, dead channel), not emergencies.

## Cost

One small file, read once at boot, overwritten rather than accumulated. No model calls in the watchdog: it's a few `pgrep`/`stat` calls per agent every two minutes. No archive that grows.
