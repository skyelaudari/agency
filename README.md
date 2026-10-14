# agency

A pattern for running a personal team of AI agents on a flat-rate Claude Code subscription.

Each agent has its own identity, its own memory, its own messaging channel, and its own scoped credentials. They run as long-lived `tmux` sessions managed by `launchd`, communicate via a file-based delegation protocol, and live in a workspace-of-workspaces directory layout.

This repo is the framework, the bootstrap installer, and the templates. It's not the agents themselves — those are yours to define. This is the scaffolding for a multi-agent personal infrastructure.

## Why this exists

Personal AI agents that run continuously and remember context across sessions are powerful, but get expensive fast when running on usage-based APIs.

Claude Code on a flat subscription removes the per-token cost.

The architecture here is how to wire this up so it holds together.

## How it works

- **One orchestrator, a few specialists.** You talk to an orchestrator agent, which handles most things itself and delegates narrow work (research, writing) to specialists through a file-based inbox. Each agent has its own identity, memory, channel, and credentials.
- **Always on, plus scheduled.** Agents run as long-lived sessions you can message at any time. Scheduled jobs run a morning brief and an evening close against one external system of record that holds open work across days.
- **Memory is files.** Daily logs record what happened. Entity dossiers record what's known about a person, project, or topic. Curated memory holds lessons and preferences. All of it is plain text you can read, grep, and correct.
- **Restarts don't lose the thread.** Before any restart, an agent writes a checkpoint, and the fresh session reads it on boot. A watchdog restarts an agent whose channel dies, but only after it checkpoints.

## Key principles

These are about the agent itself and hold regardless of the infrastructure underneath. See `docs/architecture.md` for the full set.

1. **The agent contract and the user profile are separate.** The contract defines the agent's role and rules. The profile defines who it serves, how they want to be spoken to, and how much autonomy it has.
2. **Consent is tiered per action.** Reads and internal writes are automatic. Anything that leaves the system (send, post, buy, delete) needs a confirmed yes on the exact action, target, and payload.
3. **Only trusted channels give instructions.** Everything else the agent reads (emails, documents, messages) is context, not command.
4. **Confirmed facts drive decisions. Inferred facts are evidence.** Each dossier opens with a DECIDED block holding only what the user confirmed. Plans, recommendations, and deadlines come from that block alone.
5. **Recommend, don't hand over a menu.** Report exceptions, not stable state. Never invent a deadline.
6. **Verify before claiming done.** An action counts only after it has executed and been read back, and every external action is logged.
7. **Corrections become rules.** When the user corrects the agent, the lesson is written down so it never has to be said twice. If the user ignores a suggestion, that's an answer, and the agent drops it.

## What's inside

```
agency/
├── README.md                 # This file
├── INSTALL.md                # Bootstrap walkthrough
├── docs/
│   ├── architecture.md       # The ten design choices
│   ├── identity-contracts.md # CLAUDE.md as persistent role definition
│   ├── delegation-pattern.md # File-based inbox/archive + launchd one-shots
│   ├── memory-conventions.md # Five layers: logs, curated, references, dossiers, decisions
│   ├── learning-loop.md      # Suggested vs actually-did, and promoting deltas to rules
│   ├── scheduled-briefing.md # Persistent spine, reconcile-before-flag, the chat blind spot
│   ├── session-continuity.md # Checkpoint before every restart; liveness watchdog
│   ├── profile-consent-and-action-log.md  # Quick profile, consent table, action log
│   ├── channels-setup.md     # Per-agent Telegram bot pattern
│   ├── telegram-acknowledgement-guards.md  # Hooks enforcing open/close acks
│   ├── oauth-boundaries.md   # Hard account boundaries enforced at runtime
│   └── infrastructure.md     # Tailscale + Syncthing for remote / multi-machine
├── templates/
│   ├── agent/                # Skeleton for a single agent
│   └── workspace/            # Workspace-level scaffolding
├── bin/
│   ├── bootstrap-agent.sh    # New-agent setup
│   ├── submit-delegation.sh  # Spawn a delegated agent run via launchd
│   ├── wait-delegation.sh    # Poll until a delegation completes
│   ├── cleanup-delegation.sh # Tear down a finished delegation job
│   ├── agent-session.sh      # launchd → tmux session wrapper (with checkpoint boot kick)
│   └── telegram-liveness-watchdog.sh  # Restart a deaf agent, checkpoint first
├── plists/
│   ├── agent-session.plist.template     # tmux+launchd session
│   ├── delegation-job.plist.template    # one-shot delegation
│   └── telegram-liveness.plist.template # liveness watchdog, every 2 min
└── examples/
    ├── chief-of-staff/       # Orchestrator-shaped agent
    └── researcher/           # Specialist agent
```

## Who this fits

You'll get value from this if:
- You're running multiple personal AI agents and your API bill is climbing
- You want agents that hold context across days and weeks, not single-prompt runs
- You're comfortable on macOS with `tmux`, `launchd`, and the command line
- You like a file-and-text-based architecture over hosted dashboards

You'll probably want something else if:
- You have one tightly-bounded automation task (the API at low volume is cheaper)
- You want a polished GUI; this is a terminal-and-text-files setup
- You don't want to maintain `CLAUDE.md` files for each agent

## Status

Early public release. The architecture is in production for the author's personal use; the templates and installer have been extracted from that working setup. Expect rough edges.

## License

[MIT](./LICENSE). Use, fork, and contribute freely.
