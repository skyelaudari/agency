# agency

A pattern for running a personal team of AI agents on a flat-rate Claude Code subscription, instead of paying per-token through the API.

Each agent has its own identity, its own memory, its own messaging channel, and its own scoped credentials. They run as long-lived `tmux` sessions managed by `launchd`, communicate via a file-based delegation protocol, and live in a workspace-of-workspaces directory layout.

This repo is the framework, the bootstrap installer, and the templates. It's not the agents themselves — those are yours to define. What you get here is the scaffolding that makes a multi-agent personal infrastructure tractable to set up and operate.

## Why this exists

Personal AI agents that run continuously and remember context across sessions are powerful, but the obvious shape — point each agent at the Anthropic API and let it run — gets expensive fast. A single agent doing daily inbox sweeps + occasional research can rack up `$30–60/day` in token costs. Multiply by the number of specialists you'd want and you're looking at a non-trivial monthly bill.

Claude Code on a flat subscription removes the per-token cost from the equation. A long-running session that's idle costs the same as one that's working. That changes which design choices are actually affordable: review-and-improve loops, scheduled memory writes, multiple independent agents running concurrently — all become free at the margin.

The architecture here is the answer to "how do you actually wire this up so it holds together"?

## What's inside

```
agency/
├── README.md                 # This file
├── INSTALL.md                # Bootstrap walkthrough
├── docs/
│   ├── architecture.md       # The seven design choices
│   ├── identity-contracts.md # CLAUDE.md as persistent role definition
│   ├── delegation-pattern.md # File-based inbox/archive + launchd one-shots
│   ├── memory-conventions.md # Daily logs, curated long-term, references
│   ├── channels-setup.md     # Per-agent Telegram bot pattern
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

Private, early. The architecture is in production for the author's personal use. The templates and installer are being extracted and de-PII'd from that working setup. Expect rough edges.

## License

TBD. Currently no license — assume "all rights reserved" until that changes.
