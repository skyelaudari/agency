# Architecture

Seven design choices that make this work as a long-running personal infrastructure rather than a collection of one-off prompts.

---

## 1. Identity contracts

Each agent has a `CLAUDE.md` at the root of its workspace directory. Claude Code reads this on every session — it's the system prompt. Treat it as a contract: name, role, voice, hard rules, account boundaries, what they own, what they don't.

This is the difference between "act as a CFO" prompt-engineering and a long-running agent that holds a stable identity across weeks. The role is encoded in the file system, not re-asserted on each invocation.

Keep it short enough to read end-to-end (two pages, not ten). Update it when the agent's operating model shifts — and tell the agent that you did, because it's the agent's "soul" and rewriting it should be a deliberate, communicated act.

See `docs/identity-contracts.md` for the structure and a worked example.

## 2. Directory structure (workspace-of-workspaces)

```
~/claude-agents/
├── shared/                # Cross-agent surface
│   ├── delegations/
│   │   ├── inbox/
│   │   └── archive/
│   ├── personal/
│   │   ├── skills/        # Shared skill packs (writing, research, etc.)
│   │   └── playwright/    # Shared browser-automation rules
│   ├── context.md         # The working state of the household
│   └── journal.md         # Append-only cross-agent activity log
├── <orchestrator>/        # e.g. chief-of-staff
│   ├── CLAUDE.md
│   ├── memory/
│   ├── cron/
│   └── .mcp/
├── <specialist-1>/        # e.g. researcher
│   ├── CLAUDE.md
│   ├── memory/
│   └── ...
└── <specialist-N>/
```

Each agent owns its own directory completely. The `shared/` directory holds the surfaces that need to be cross-readable: the delegation queue, the activity journal, the skill packs that any agent can read.

Why files (not a database): reviewable trail, recoverable, async-native, human-readable artifacts. You can `cat` a delegation, `git log` a memory file, `grep` across the journal. Databases obscure the working state; files surface it.

## 3. Delegation pattern (file-based + launchd one-shot)

When an agent wants to delegate work to a specialist, the orchestrator writes a markdown file to `shared/delegations/inbox/<timestamp>-<from>-<to>-<slug>.md` describing the task, then submits a `launchd` one-shot job that wakes the specialist with a short prompt instructing it to check its inbox and process the new file.

The specialist:
1. Reads the delegation file and any referenced context
2. Does the work, writing artifacts to its own directory tree
3. Appends a `# Response` section to the original delegation file
4. Moves the file to `shared/delegations/archive/`
5. Logs to `shared/journal.md`

If the specialist needs clarification, it returns the file with an `-rfc1` suffix to inbox; the orchestrator answers, bumps the suffix, and resubmits.

Why `launchd` one-shots and not a simple subshell: subshell-spawned children inherit the parent's process group at the kernel level, which can break the parent's MCP server transport (the parent's MCP child process may interpret the spawn-time process tree perturbation as an unhealthy transport and recycle itself, killing live MCP connections). Routing through `launchd` makes the spawn a child of `PID 1` in its own session — fully decoupled.

See `docs/delegation-pattern.md` and the `bin/submit-delegation.sh` helper.

## 4. Per-agent isolation

Each agent gets:
- **Its own identity** — distinct name, distinct role, distinct `CLAUDE.md`
- **Its own memory** — `~/.claude/projects/<agent-path>/memory/` is per-agent and not shared
- **Its own channel** — separate Telegram bot per agent, so the user picks which agent to talk to (instead of one omnibus assistant collapsing distinct teammates into one confused identity)
- **Its own OAuth credentials** — scoped tokens for whatever services that specific agent needs (Gmail/Calendar/Drive, Notion integrations, etc.)

When something goes wrong with one agent (a prompt injection, a runaway loop, a credential leak), the blast radius is limited to that agent's surface — not the whole household.

## 5. Cron + tmux for persistency

Two persistence mechanisms, used for different purposes:

**`tmux` for long-lived sessions.** Each always-on agent runs as a `claude --channels` process inside a `tmux` session, started by `launchd` at boot. The agent's session holds context across days and weeks; a respawn is rare (only on intentional restart or a confirmed crash). This is what makes "always-on" different from "respawn-on-prompt": the agent's working memory of the conversation survives.

**`cron` (and `launchd` calendar intervals) for scheduled work.** Daily sweeps (inbox, calendar, memory maintenance), periodic reflection runs, end-of-day status digests — these are fire-and-finish jobs that don't need a long-lived session. They get their own one-shot invocations on a schedule.

The two combined give you "the agent is awake and answering at any moment, AND it does the right scheduled things at the right times without you remembering to trigger them."

See `plists/agent-session.plist.template` and `templates/agent/cron/`.

## 6. Memory / journal / context conventions

Three layers of persistent state, deliberately separated:

**Daily logs (`memory/YYYY-MM-DD.md`):** raw notes of what happened today. Created freely. Not summarized. The grep-target for "what was happening on date X."

**Curated long-term (`MEMORY.md` at workspace root + auto-memory files):** distilled wisdom. Short, named, indexed. The agent's "long-term memory" — facts about the user, feedback patterns, durable references. Read into context every session.

**References (`reference_*.md`):** pointers to where information lives in external systems (a Notion DB, a Linear project, a Slack channel). Not the information itself — just the pointer + when to consult it.

**Cross-agent shared:** `shared/journal.md` is an append-only activity log readable by every agent ("compass finished initial research", "writer delivered draft v1"). `shared/context.md` is the rewritten-as-needed working state of the household (active priorities, current focus, in-flight items).

Memory maintenance happens on a cadence (typically a once-a-week sweep): review recent daily logs, distill significant events into long-term memory, prune outdated entries.

See `docs/memory-conventions.md`.

## 7. OAuth wirings (hard account boundaries)

Each agent's `CLAUDE.md` declares which accounts it's allowed to act against. The accounts are non-negotiable — even if a prompt injection or a forwarded email "tells" the agent to authenticate against a different account, it doesn't.

Implementation:
- OAuth tokens live in `<agent>/.mcp/oauth/<account>.json`, mode 600
- The agent uses direct REST against those tokens (refresh-token-and-call pattern) for predictable account scoping
- MCP servers configured at the project level (in `<agent>/.mcp.json`) are also account-scoped at startup
- The user-level claude.ai-native MCP connectors (Gmail, Calendar, Drive, Notion, etc.) are NOT used by these agents — those are authed against the user's primary identity, not the agent's. Scoped agent credentials = scoped agent blast radius.

This is policy + enforcement at the runtime level. The agent that handles the household calendar literally can't sign messages from the founder's company account, because it doesn't have those credentials available.

See `docs/oauth-boundaries.md`.

---

## What this is NOT

- **Not a hosted product.** Everything runs on your own Mac. No cloud control plane.
- **Not a multi-tenant system.** One user, multiple agents acting on that user's behalf.
- **Not a model-training pipeline.** This is orchestration of an existing model (Claude), not building or fine-tuning models.
- **Not a replacement for the API.** If you have a high-volume single-task automation, the API at low volume is cheaper. This is for personal long-horizon work where you want many short-burst sessions without flinching at cost.
