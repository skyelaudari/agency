# Workspace template

Starter scaffolding for a new agent workspace. Copy this directory into the parent of your agent dirs (the `WORKSPACE_ROOT`) before bootstrapping any agents.

```
your-workspace-root/
├── shared/                 ← from this template
│   ├── journal.md
│   ├── context.md
│   ├── delegations/
│   │   ├── inbox/
│   │   └── archive/
│   └── personal/
│       └── skills/
└── <your-agents>/          ← created later by bootstrap-agent.sh
```

The `shared/` directory holds cross-agent surfaces:

- **`journal.md`** — append-only activity log readable by every agent
- **`context.md`** — working state of the household, rewritten as state shifts (always update the `last-edited:` header)
- **`delegations/inbox/`** — where delegation files land for processing
- **`delegations/archive/`** — where completed delegations are moved
- **`personal/skills/`** — shared skill packs (writing-feedback, research methodology, etc.) any agent can read

Quick install:

```bash
WORKSPACE_ROOT=~/agents
mkdir -p $WORKSPACE_ROOT
cp -R agency/templates/workspace/* $WORKSPACE_ROOT/
```

Then `bootstrap-agent.sh` creates new agents alongside the `shared/` dir.
