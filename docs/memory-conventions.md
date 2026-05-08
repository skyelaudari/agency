# Memory conventions

Three layers of persistent state, deliberately separated. The separation is what keeps memory useful at month six instead of becoming a junk drawer.

## The three layers

### 1. Daily logs (raw notes)

Path: `<agent>/memory/YYYY-MM-DD.md`

What goes in: anything from today worth recording without filtering. What got decided, what blocked, what was learned, who asked for what, what surprised. Free-form. No summarization. No template required.

Write freely. Don't worry about whether something is "important enough." If it might matter later, write it down.

These files are the grep target for "what was happening on date X." They're disposable in the long run but invaluable in the short run.

### 2. Curated long-term (`MEMORY.md` + auto-memory files)

Path: workspace root `MEMORY.md` plus per-topic files in the auto-memory directory.

What goes in: distilled wisdom. Lessons that survived re-reading. Things durable enough to keep across many sessions.

Structure each entry as:
- A short title
- A one-line description / hook
- The rule itself
- **Why:** the reason (often a past incident or an explicit user instruction)
- **How to apply:** when this kicks in, with concrete examples

Categorize by type:
- **`user_*.md`** — facts about the user's role, preferences, knowledge
- **`feedback_*.md`** — guidance the user has given about how to operate
- **`project_*.md`** — ongoing initiatives, current state, deadlines
- **`reference_*.md`** — pointers to where information lives in external systems

`MEMORY.md` is the index — one line per memory file, around 150 chars. It's auto-loaded into context every session, so keep it concise. Lines past ~200 will be truncated.

### 3. References

What goes in: pointers to where information lives in external systems. Not the information itself — just the pointer plus when to consult it.

Example:
- "Pipeline bugs are tracked in Linear project INGEST"
- "Oncall latency dashboard at grafana.internal/d/api-latency — check when editing request-path code"

The point of references is to keep external systems as the source of truth and the agent's memory as a routing layer.

## Cross-agent shared memory

Two files in `shared/`:

**`shared/journal.md`** — append-only activity log. Any agent can write a line. The format is `[YYYY-MM-DD HH:MM] [agent] description`. Useful for "what's been happening across the household this week."

**`shared/context.md`** — the working state of the household. Active priorities, current focus, in-flight items. Rewritten when major state shifts (a new initiative starts, a project closes, a priority changes). Always update the `<!-- last-edited: YYYY-MM-DD HH:MM by <agent> -->` header on rewrite to surface conflicts.

Per-agent memory stays per-agent. The shared layer is for surfaces that need to be cross-readable, not for everything every agent does.

## Maintenance cadence

Once-a-week sweep:
1. Skim recent daily logs (last 7-14 days)
2. Identify patterns, lessons, durable insights
3. Distill into long-term memory entries (new files or updates to existing ones)
4. Prune entries that are stale or no longer correct
5. Update `MEMORY.md` index to reflect changes

The sweep takes 10-20 minutes and is the single most important hygiene practice for a long-running agent. Skip it for a month and the memory becomes either out of date (agent acts on facts that aren't true anymore) or untrusted (agent stops referencing memory because too much of it is stale).

## When to write memory

**Always write durably (not "remember this in conversation"):**
- When the user gives a feedback correction ("don't do X" / "always do Y")
- When the user validates an unusual approach ("yes, that was right")
- When you learn a fact about the user's role, preferences, network
- When a project's state changes (ownership, deadline, priority)
- When a calibration moment happens that you'll want to recall next session

**Don't write:**
- Code patterns, file paths, architecture (read the code instead)
- Git history, who-changed-what (`git log` is authoritative)
- Debugging fix recipes (the fix is in the code; commit message has the context)
- Anything in CLAUDE.md (don't duplicate)
- Ephemeral task details from the current session

## Memory and other persistence mechanisms

Memory is one of several persistence mechanisms:
- **Plans** are for in-conversation alignment on approach. Don't substitute memory for plan.
- **Tasks** are for tracking discrete steps in the current session. Don't substitute memory for tasks.
- **Memory** is for what should be recallable across future sessions.

The test: would a future-me, in a different conversation, want to know this? If yes, memory. If only this-session, plan or task.

## Anti-patterns

**Mental notes.** "I'll remember to do X next time." You won't. The session ends, the context resets, the lesson is lost. Write it down.

**Memory sprawl.** A new file for every minor variation. Update existing memory entries when the lesson is an extension of an existing rule.

**Snapshot memories.** Activity logs and architecture snapshots that are frozen in time and become misleading. Memory should be rules and facts that hold, not state that drifts.

**Over-detailed memories.** A 500-word memory file for a one-line rule. The agent reads memory at the start of every session — keep it short or it gets skimmed.

**Forgetting to maintain.** Without the weekly sweep, memory rots. Build the sweep into a recurring task or schedule.
