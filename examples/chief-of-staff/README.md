# Example: chief-of-staff (Atlas)

A concrete, fictional worked instance of an orchestrator agent.

**Persona:** Atlas, chief of staff to a fictional founder named Alex Reeve. Atlas runs point on calendar, inbox, household coordination, and delegates research + long-form writing to specialists.

**What's in this example:**
- `CLAUDE.md` — the full identity contract, with placeholder accounts substituted in.
- (In a real install, you'd also see `MEMORY.md`, `memory/YYYY-MM-DD.md` daily logs, `cron/` scheduled jobs, `.mcp/` for OAuth tokens — those are gitignored / state, not framework.)

**How to use as a starting point:**
1. Copy `CLAUDE.md` to your new agent's directory
2. Replace identity (Atlas → your agent name) and persona (Alex Reeve → you)
3. Replace `@reeve.com` with your domain
4. Replace `<alex-telegram-user-id>` with your Telegram user ID
5. Adjust the specialists list to match the agents you're actually running
6. Trim sections that don't apply (e.g., daily sweeps if your agent isn't running scheduled work)

This example reads as a complete, deployable contract. Length: ~165 lines / two pages. Read end-to-end in one sitting before adapting.
