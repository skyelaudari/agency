# Example: researcher (Compass)

Concrete worked instance of a research specialist agent.

**Persona:** Compass, research specialist for Alex Reeve (the same fictional founder used in the chief-of-staff example). Compass takes delegated research tasks from Atlas (chief-of-staff) and returns structured deliverables.

**What's different from the chief-of-staff example:**
- Specialist (not orchestrator) — receives delegations from Atlas, doesn't dispatch to other agents
- Tighter scope — research only; doesn't touch calendar, inbox, or external action surfaces
- Different OAuth scopes — drive.readonly + sheets (for writing deliverables); not gmail / calendar
- Different cadence — no daily sweep; runs only when delegated to or when Alex pings directly
- Web access discipline — view-only on authenticated sites (the user is logged in as Alex; Compass must not engage)

Both example agents share:
- Hard account boundaries (per-agent OAuth, never crossing scopes)
- Trusted sender channels (Telegram + delegation inbox)
- Confidentiality default ("don't share, ask Alex")
- Memory + journal conventions
- The platform formatting / acknowledgment rules

**How to use as a starting point:**
1. Copy `CLAUDE.md` to your new specialist's directory
2. Replace identity (Compass → your specialist's name)
3. Adjust OAuth boundaries to the scopes the specialist actually needs (the principle: narrowest scope that lets the specialist do its job)
4. Replace the persona name (Alex Reeve → you) and trusted channels with your own
5. Trim or extend the delegation-processing section to match your team's flow
