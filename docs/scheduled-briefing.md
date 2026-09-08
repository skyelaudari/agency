# Scheduled briefing

An agent that only reacts to messages goes quiet on days nobody talks to it. A scheduled sweep with nothing shared to read fixes the silence but creates a worse problem: it re-asks things the user already answered, because a cold job has no access to the conversation where they answered it. This is the pattern that gets both right — a persistent spine external systems can read, and two fixed jobs that render and update it.

## The persistent spine

One external system — a database, a project-tracker board, a single "active items" table — holds state across days. Not memory files, not chat history: those are the agent's own journal (see `docs/memory-conventions.md`), and a scheduled job that has to parse yesterday's freeform notes to find out what's still open doesn't scale past a few weeks.

- A **morning job** reads the spine and **renders** it into an exceptions-only rundown: what's due, what's overdue, what's landing soon. It publishes the rundown and delivers a short pointer to it on whatever channel the user actually checks.
- An **evening job** re-sweeps for movement since morning and **updates** the spine: close what's done, add what's new, carry forward what isn't.
- Close feeds render feeds close. The loop is what guarantees nothing drops between days without anything having to read the interactive session's history — the spine is doing that job instead.

## Cadence

Two jobs always report, because a quiet day is exactly the case the user needs confirmed, not assumed:

- **Morning brief.** Runs every day, even a quiet one. Silence from the agent on a day nothing happened is indistinguishable from the agent being broken.
- **Evening close.** Same reasoning, in reverse — it's the bookend that sets up tomorrow.

Lighter mid-day sweeps sit between them and behave differently: **report only if something changed.** No "all clear" ping. The bookends are for confirming the system is alive either way; the mid-day sweeps are for catching movement, and manufacturing a ping when nothing moved trains the user to skim past every message from the agent, bookends included.

## Reconcile before flag

Before surfacing anything as open or pending, check whether reality already closed it:

- Did the user already respond, on a channel the agent can read? (sent mail, a reply in a thread)
- Did the counterparty already respond?
- Is the thing already on the calendar / already booked?
- Does a finished artifact already exist — a delivered document, a completed row elsewhere?

Close these in the spine **before** composing the brief, not after noticing them while writing it. Surfacing something the user already handled is the primary failure mode of a briefing system: it forces them to re-decide something they closed, which is the exact cognitive load the system exists to remove.

## The blind spot: scheduled jobs can't see the chat

See `docs/memory-conventions.md`'s "Scheduled jobs only see durable state" section for the general form of this problem. Inside a briefing pipeline specifically, it shows up as **calendar and to-do anomalies that were already explained, verbally, in a conversation the scheduled job never reads.**

> **The incident.** A decision superseded an existing plan; the new decision got its own tracked record, but the old record — which predated it — was never closed. Separately, the user explained an odd-looking calendar booking directly in chat; the agent acknowledged it and logged it to its own daily journal. The next morning's scheduled brief read the spine fresh, as it always does, and flagged both: the old record as a conflict with the new one, and the calendar booking as unexplained. Both flags were *individually* correct given what the job could see. Neither should have still been flaggable.

The fix, in the job's own reconcile step:

1. Before flagging any calendar item or to-do as unexplained, query the spine directly for a matching record **in any status** — including closed and cancelled — not just the filtered view a normal render pass uses. The explanation usually lives in a closed record's notes field; a status filter built for the happy path hides exactly the row that answers the question.
2. If nothing matches, fall back to a **bounded** grep of the relevant daily log (today's and/or yesterday's, not the whole journal) for the item's keyword. This catches the case where an explanation was given in chat but the write-to-spine discipline slipped before the job ran. It is a cheap safety net, not a substitute for step 1 — a raw journal is too unstructured to be the primary check, and this fallback should say so in the brief if it's the thing that resolved the anomaly, so the gap stays visible instead of silent.
3. On the interactive side, this only works if the discipline holds: **the moment something is resolved or explained in conversation, write it to the spine that same turn**, not just to the agent's own journal. And **search the spine before creating a new record on a topic** — the stale-duplicate half of the incident above is caught by this alone.

## Template discipline

A briefing that reports everything is a briefing nobody reads past the second day.

- **A hard word ceiling.** If the day's exceptions don't fit inside it, they weren't exceptions — cut, don't pad.
- **Never re-paste the spine.** The spine is a system of record the user can already open; link to it, don't republish it inline. Whatever plumbing renders "what's overdue / what's due / what's coming" is input for composing the brief, not content to reproduce verbatim.
- **No section that reports nothing happening.** No "inbox: clear," no paragraph about an empty calendar. A clear day is one trailing clause, or it's absent entirely.
- **Absorb the decision.** If an item reads dead, cut it and say what changed — don't hand the prune decision back to the user with "say the word and I'll clean this up."
- **One action per record, and the record must match the ask.** If a checkbox or a tick closes an entire tracked item, the brief line pointing at it must mean the same scope as that item — a narrow one-line ask backed by a record that means much more than the line says will close far more than the user intended when they tick it. Split it onto its own record first if the two don't match.

## Editing a running schedule

Most schedulers (`launchd`, `cron`, similar) cache a job's command or prompt at load time. Editing the on-disk job file does not take effect on its own — the running job keeps using what it loaded until it's reloaded. For `launchd` specifically: `launchctl bootout gui/<uid>/<label>` followed by `launchctl bootstrap gui/<uid> <path-to-plist>`. This bites people constantly, because the edit looks committed — the file on disk is right — and the job still runs on the old text until it's actually reloaded.
