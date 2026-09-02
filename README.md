# agency

A pattern for running a personal team of AI agents on a flat-rate Claude Code subscription.

Each agent has its own identity, its own memory, its own messaging channel, and its own scoped credentials. They run as long-lived `tmux` sessions managed by `launchd`, communicate via a file-based delegation protocol, and live in a workspace-of-workspaces directory layout.

This repo is the framework, the bootstrap installer, and the templates. It's not the agents themselves — those are yours to define. This is the scaffolding for a multi-agent personal infrastructure.

## Why this exists

Personal AI agents that run continuously and remember context across sessions are powerful, but get expensive fast when running on usage-based APIs.

Claude Code on a flat subscription removes the per-token cost.

The architecture here is how to wire this up so it holds together.

## What's inside

```
agency/
├── README.md                 # This file
├── INSTALL.md                # Bootstrap walkthrough
├── docs/
│   ├── architecture.md       # The seven design choices
│   ├── identity-contracts.md # CLAUDE.md as persistent role definition
│   ├── delegation-pattern.md # File-based inbox/archive + launchd one-shots
│   ├── memory-conventions.md # Five layers: logs, curated, references, dossiers, decisions
│   ├── learning-loop.md      # Suggested vs actually-did, and promoting deltas to rules
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
│   └── cleanup-delegation.sh # Tear down a finished delegation job
├── plists/
│   ├── agent-session.plist.template     # tmux+launchd session
│   └── delegation-job.plist.template    # one-shot delegation
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
