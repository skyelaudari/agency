# Memory conventions

Five layers of persistent state, deliberately separated. The separation is what keeps memory useful at month six instead of becoming a junk drawer.

The first three are the base set and are enough to start. Layers 4 and 5 emerge once an agent has been running long enough to accumulate real history — they solve failures the first three cause, and both are described with the incident that produced them.

## The layers

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

### 4. Entity dossiers (the read-optimized layer)

Path: `<agent>/memory/entities/<slug>.md`, with an `_INDEX.md`

Daily logs are a **journal**: organised by time, optimised for writing. But almost every real retrieval question is entity-shaped — *"what do we know about Acme?"* — and a journal can only answer *"what happened on July 3rd?"* That mismatch is how a long-running agent re-derives analysis it already did and loses facts it already had.

One file per live opportunity, person, or workstream. The rules that make it work:

- **Read the dossier FIRST**, before any work touching that entity. Step one, not an optional check.
- **Every fact carries a source and a date.** On conflict, the later date wins — resolve it from the record. Asking the user to adjudicate something the dates already settle is the failure this exists to prevent.
- **Record conclusions, not just events.** Keep a "positions already taken" section so analysis compounds instead of restarting. Withdrawn positions stay, marked withdrawn — the reversal is information.
- **Write on the trigger, not at session end.** Sessions get cut off mid-thought. The moment the user states a fact or a counterparty discloses something, update the dossier *before continuing the conversation*.
- **Distil on ingest.** Reading an expensive source — a long transcript, a dense document — must produce a durable distillate. **Anything read twice is a process failure.**
- **Prune on supersede.** When a section is retired, cut it to a one-line stub saying so. Dossiers that only grow become unreadable, and stale full-text sections are what the agent reasons from by accident.

> **The incident.** In a single evening an agent re-derived a strategic thesis it had written three weeks earlier, re-presented the user's own idea back to them as a new finding, and asked them to adjudicate a number they had explained the day before. All of it was on disk. None of it was retrievable *by entity*.

### 5. The decision ledger (`DECIDED`)

Path: a `🔒 DECIDED` block at the top of each entity dossier.

Dossiers accrete everything an agent learns, with no line between **what the user decided** and **what the agent found while looking**. The agent then builds plans on its own research as though the user had endorsed it.

- **Every dossier opens with a `DECIDED` block** — the user's actual positions, in their words, dated. Everything below it is evidence.
- **Only the DECIDED block drives recommendations, plans, and deadlines.** A number from the evidence sections is promoted only when the user confirms it.
- **Before recording a fact, name the decision it serves.** If it can't name one, don't write it down. A hedged note is exactly the kind that gets silently promoted later — either it's load-bearing and goes in DECIDED, or it's noise and goes nowhere.
- **Never invent a deadline.** A clock is real only if the user set it or a counterparty stated it.

> **The incident.** An agent modelled a purchase against a valuation the user had never intended to use, and manufactured a deadline from an offer expiry on an asset they weren't selling. Both numbers were real. Neither was theirs.

**None of this discourages surfacing.** Raise anything, once. If the user doesn't engage, drop it — non-engagement is an answer, not a gap. Surfacing is unconstrained; it is the *decision layer* that is gated.

### A plan is not a fact

This one cuts across layers 1, 4 and 5, and it is the most common way a long-running agent annoys the person it works for.

Agents write plans down well. They record outcomes badly. An unresolved plan and an open question are **indistinguishable on disk**, so the next session reads the plan, finds no recorded result, and re-asks something the user already answered.

**When the user states an outcome — a thing happened, a thing did not happen, someone holds or does not hold a role — write it into the dossier in that same turn, above the plan it resolves, and annotate the plan so it cannot be re-read as pending.** For status that sessions keep re-deriving, put a hard-facts block at the top of the file.

> **The incident.** A user corrected the same fact three times across three sessions. A grep of the whole memory tree found zero occurrences of it. The plan that implied the question was written in three places; the answer had never been written once.

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

**Journal-only memory.** Daily logs with no entity layer. The agent can tell you what happened on a date and nothing about the thing you actually asked about.

**Promoting your own research.** Treating something the agent found as though the user had decided it. This is the failure the `DECIDED` block exists to prevent, and it is invisible until a plan is built on it.
