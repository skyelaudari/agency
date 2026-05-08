# Installation

Bootstrap walkthrough for going from "fresh Mac" to "first agent running" in roughly 30 minutes.

## Prerequisites

You need:
- macOS (Sequoia or later recommended; works on Sonoma)
- A Claude Code subscription (the framework is built around the flat-rate runtime)
- Comfort on the command line: `git`, `bash`, basic `tmux` use

You'll also install:
- **Node** (via `nvm` recommended) — for the `claude` CLI
- **tmux** — for the persistent session pattern
- **Homebrew** — to install the above

## 1. Install dependencies

```bash
# Homebrew (if not already)
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# nvm
brew install nvm
mkdir -p ~/.nvm
# Add nvm sourcing to your shell rc — see brew install output

# Node + the claude CLI
nvm install 22
nvm use 22
npm install -g @anthropic-ai/claude-code

# tmux
brew install tmux
```

Verify:

```bash
which claude  # should print a path under ~/.nvm/versions/node/...
which tmux    # should print /opt/homebrew/bin/tmux or similar
```

Then `claude` once interactively to log in to your Anthropic account:

```bash
claude
# follow the auth prompts; type /exit when done
```

## 2. Set up the workspace

Choose where your agent fleet will live. The default convention is `~/agents/` but anywhere works.

```bash
export WORKSPACE_ROOT=~/agents
mkdir -p $WORKSPACE_ROOT
cd $WORKSPACE_ROOT
```

## 3. Clone the agency framework

```bash
cd $WORKSPACE_ROOT
git clone <agency-repo-url> agency
cd agency
chmod +x bin/*.sh
```

Add the bin scripts to your PATH (optional but convenient):

```bash
echo 'export PATH="$HOME/agents/agency/bin:$PATH"' >> ~/.zshrc
source ~/.zshrc
```

## 4. Initialize the workspace's shared layer

```bash
cd $WORKSPACE_ROOT
mkdir -p shared/{delegations/inbox,delegations/archive,personal,personal/skills}
touch shared/journal.md shared/context.md
```

The `shared/` layer holds cross-agent surfaces:
- `delegations/inbox/` and `delegations/archive/` — where delegation files flow
- `personal/skills/` — shared skill packs that any agent can read
- `journal.md` — append-only cross-agent activity log
- `context.md` — current state of the household, rewritten as state shifts

## 5. Bootstrap your first agent

The framework includes a `bootstrap-agent.sh` helper. Pick a name:

```bash
cd $WORKSPACE_ROOT
USER_FIRST_NAME="Alex" agency/bin/bootstrap-agent.sh chief-of-staff
```

This creates `$WORKSPACE_ROOT/chief-of-staff/` with:
- `CLAUDE.md` (scaffolded from template, ready to edit)
- `MEMORY.md` (empty)
- `memory/<today>.md` (initial daily log)
- `cron/` (empty, for scheduled jobs you'll add later)
- `.mcp/oauth/` (mode 700, for scoped OAuth tokens you'll add later)
- `.claude/channels/telegram/` (where the channels-mode plugin will write state)
- `logs/` (where launchd will write the session's stdout/stderr)

It also writes a launchd plist to `~/Library/LaunchAgents/com.agency.chief-of-staff.session.plist`.

Don't start the session yet. First, customize the agent.

## 6. Customize the agent's identity contract

Open `$WORKSPACE_ROOT/chief-of-staff/CLAUDE.md` and replace the placeholders:
- `{{AGENT_ROLE_ONE_LINER}}` — what this agent does, one short sentence
- `{{AGENT_VIBE}}` — voice and manners (e.g., "Sharp, calm, resourceful. Run point.")
- `{{AGENT_EMOJI}}` — a single emoji
- `{{AGENT_PRIME_DIRECTIVE}}` — the one thing this agent prioritizes above other concerns
- `{{SERVICE_*}}`, `{{ACCOUNT_*}}`, `{{TOKEN_PATH}}` — your account boundaries
- `{{TRUSTED_CHANNEL_*}}` — your trusted communication channels
- `{{USER_TELEGRAM_ID}}` — your Telegram user ID (see step 7)
- Any other `{{ALL-CAPS-IN-CURLIES}}` placeholders specific to your setup

Read `docs/identity-contracts.md` for the full structure and a worked example. Length target: two pages, not ten.

## 7. (Optional) Set up the agent's Telegram channel

If you want to message the agent on Telegram instead of running it interactively:

1. Open Telegram, message `@BotFather`, run `/newbot`, follow the prompts. Save the API token.
2. DM `@userinfobot` to get your numeric Telegram user ID.
3. Create the channel access file:

```bash
cat > $WORKSPACE_ROOT/chief-of-staff/.claude/channels/telegram/access.json <<EOF
{
  "version": 1,
  "default_chat_id": "<YOUR-USER-ID>",
  "bot_token": "<BOT-API-TOKEN>",
  "allowlist": [
    {"chat_id": "<YOUR-USER-ID>", "label": "you"}
  ]
}
EOF
chmod 600 $WORKSPACE_ROOT/chief-of-staff/.claude/channels/telegram/access.json
```

See `docs/channels-setup.md` for full details.

## 8. (Optional) Add scoped OAuth tokens

If your agent will use Gmail / Calendar / Drive / Notion / etc., add scoped tokens at `$WORKSPACE_ROOT/chief-of-staff/.mcp/oauth/<service>.json` (mode 600).

See `docs/oauth-boundaries.md` for the OAuth flow + format.

## 9. Start the agent

```bash
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.agency.chief-of-staff.session.plist
```

Verify:

```bash
launchctl list | grep com.agency.chief-of-staff
# Should show a PID + 0 (not -1 or another error code)

tail -f $WORKSPACE_ROOT/chief-of-staff/logs/session.out
# Should show claude startup output
```

Connect to the running tmux session to inspect or interact:

```bash
tmux -L chief-of-staff attach -t chief-of-staff
# Detach with Ctrl-B then D
```

If you set up Telegram, send the bot a message — the agent should respond.

## 10. Add specialists

Repeat steps 5–9 for additional agents:

```bash
USER_FIRST_NAME="Alex" agency/bin/bootstrap-agent.sh researcher
USER_FIRST_NAME="Alex" agency/bin/bootstrap-agent.sh writer
# etc.
```

Each gets its own agent dir, its own CLAUDE.md, its own launchd-supervised tmux session, and (if you set them up) its own Telegram bot.

## Stopping / restarting an agent

```bash
# Stop
launchctl bootout gui/$(id -u) ~/Library/LaunchAgents/com.agency.<agent>.session.plist

# Or just kill the tmux session — launchd KeepAlive will restart it within 10s
tmux -L <agent> kill-session -t <agent>

# Permanent stop (remove launchd job)
launchctl bootout gui/$(id -u) ~/Library/LaunchAgents/com.agency.<agent>.session.plist
rm ~/Library/LaunchAgents/com.agency.<agent>.session.plist
```

## Troubleshooting

**"agent not responding"** — check `tail -f $WORKSPACE_ROOT/<agent>/logs/session.err`. Common causes: bad `CLAUDE.md` (parse error), missing OAuth token referenced in CLAUDE.md, claude binary path mismatch in plist.

**"launchctl bootstrap failed"** — usually means the label already exists. Run `launchctl bootout gui/$(id -u) <plist-path>` first, then re-bootstrap.

**"Telegram bot getting 409 Conflict"** — two processes are polling the same bot. Most often caused by a duplicate session somewhere. Check `ps aux | grep claude` for duplicates; check other machines if you have a multi-machine setup.

**"agent can't write files"** — the launchd session was started without `--dangerously-skip-permissions`, or macOS App Management permission is needed. Check the plist; check System Settings → Privacy & Security → App Management.

**"MCP server keeps disconnecting after I delegate"** — you're spawning specialists from a subshell instead of via `submit-delegation.sh`. See `docs/delegation-pattern.md`.

## What you have now

After this walkthrough:
- A workspace at `$WORKSPACE_ROOT` with shared/ + one or more agents
- Each agent supervised by launchd, running in its own tmux session
- Each agent (optionally) reachable via its own Telegram bot
- A delegation primitive (`submit-delegation.sh`) for handing work between agents
- Identity contracts (CLAUDE.md per agent) defining role + boundaries

The framework gives you the scaffolding. The agents themselves — what they do, how they think — are yours to define in their CLAUDE.md files.
