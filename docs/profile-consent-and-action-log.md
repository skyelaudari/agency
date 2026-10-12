# Profile, consent table, action log

Three small structural pieces added after surveying how 2026's consumer personal-agent products handle personalization, consent, and accountability. The question was narrow: which of their architecture, process, and memory choices carry over to a setup that's one Claude Code session per agent on a Mac, with file-based memory, no app, and no custom model?

The answer was "not much of the product surface, but three patterns." Each is a file or a section, not new infrastructure.

## 1. A compact profile at the top of `CLAUDE.md`

**The pattern.** The products with the best-reviewed personalization keep a small, always-loaded profile layer separate from the deep archive underneath — a tight block of life context, autonomy calibration, and communication style loaded on every turn, whether implemented as an injected profile, a single editable memory summary, or an on-device index. All are small, fast, and loaded every time.

**Why it was needed here.** A long-running agent's `CLAUDE.md` accretes. Credential paths, OAuth port history, and dated incident post-mortems all matter for correctness. But they end up interleaved with the few lines a session actually needs first: who it serves, how to talk to them, and what it may do without asking.

**What to do.** Put a short "Quick profile — read this first" block directly under the title, before Identity:

- **Who:** the role, in one line
- **Voice:** the user's communication preferences, as stated by them
- **Autonomy today:** one line for internal work, one for external actions, with a pointer to the full consent table
- **Trusted channels:** the exact channel identifiers, nothing else
- **Before starting work on a named topic, company, or person:** check `memory/entities/_INDEX.md` for an existing dossier and read it first
- **Current priority:** a pointer to the section that holds it, not a copy

Keep the block itself short. If it starts collecting detail, that detail belongs further down the file.

**The entity-index line replaces a second index file.** The first idea was a separate always-loaded index mirroring `memory/entities/_INDEX.md`. It was rejected because it would duplicate existing content and need to be kept in sync, which is its own stale-duplicate risk. `CLAUDE.md` is already loaded in full every session, so one line in the profile gives the same guarantee with no new file.

## 2. An action consent table

**The pattern.** The better-gated products assign each action category (send, publish, delete, purchase, production change) either "always allow" or "require approval." The consent spectrum across the category tracked its trust incidents closely: the products with standing transaction authority and no real gate were the ones with publicly reported failures — an unauthorized send, and a prompt-injection exploit that worked because the agent was allowed to act on injected instructions. The products with explicit per-instance consent had none reported.

**Why it was needed here.** The policy already existed, but it was scattered across many paragraphs: ask first for anything external, auto-allow internal writes, plus specific booking and capture rules. Scattered policy makes it likely that the next rule gets added inconsistently with the others.

**What to do.** Gather it into one table under "External vs internal" in `CLAUDE.md`. Present it as a legibility fix, not a new rule. Where the table and more specific prose disagree, the prose wins and the table gets corrected.

| Action | Default | Detail |
|---|---|---|
| Read, research, browse view-only | Auto | Browser automation is read-only by default |
| Update own memory, dossiers, action log, `CLAUDE.md` | Auto | Tell the user when `CLAUDE.md` changes |
| Writes to the shared system of record (to-dos, CRM rows) | Auto | Real-time; see `docs/scheduled-briefing.md` |
| Create docs/files the agent authors | Auto | Mark them as agent-created |
| Delegate to a specialist | Auto | Internal coordination |
| Send email | **Never** / Ask first | Per the agent's account boundaries |
| Post, comment, like, connect, apply, message on an authenticated site | Ask first | Confirm the exact action, target, and payload, then wait for go-ahead |
| Purchases, anything spending money | Ask first | |
| Delete a file or durable record | Ask first | `trash` > `rm`; archive or cancel records instead of deleting them |
| Share the user's data with anyone, including sibling agents | **Never** without per-instance say-so | See the confidentiality rule |
| Restart another agent's session | Only on the user's explicit instruction | One standing exception: the liveness watchdog, checkpoint first. See `docs/session-continuity.md` |

**What doesn't carry over: broad standing authority.** The most advertised capability across the category — agents that act on the user's behalf without asking — is the one that produced the reported incidents. Ask-first for external actions is the right answer to that failure, not a limitation to engineer around.

## 3. An append-only action log

**The pattern.** The better-audited products ship an optional, structured action recording, separate from conversational memory. A journal entry isn't an audit trail. Testers of the less-audited products repeatedly couldn't answer "what did it actually do?"

**Why it was needed here.** Daily logs are narrative. They work well for context and badly for a fast lookup of what external actions this agent took, on which account, and when. Two recurring failures depend on that lookup: claiming something was done without having executed it, and scheduled jobs that can't see the interactive conversation (`docs/memory-conventions.md`, "Scheduled jobs only see durable state").

**What to do.** Create `memory/action-log.md`, with one line per external-facing action (anything that reaches outside the agent's own files, per the consent table), appended immediately after taking it:

```
YYYY-MM-DD HH:MM TZ | account | action | target
```

That makes "did I actually do that" a grep instead of a re-read. It also gives the closure rule (never claim done without executing and verifying) something cheap to verify against.

If the log is still empty a week after it's created, the discipline isn't sticking. Treat that as a signal, not as a quiet week.

## What was deliberately not adopted

Each of these is impressive in its product and wrong for a household-scale agent setup:

- **Avatars, realtime video personas, wearable integration.** These are engagement surfaces for a mass-consumer app. A text channel to one user has no audience for a face.
- **A custom fine-tuned model behind an inference proxy.** Out of scope. This framework orchestrates an existing model.
- **A per-user cloud VM with browser-broker leasing.** That solves a scaling problem (millions of users sharing a browser pool) that doesn't exist here. The Mac and a Playwright profile already are the persistent machine with a browser.
- **Vector/embedding memory as the primary store.** None of the surveyed products use it for core durable memory — the ones with the best-reviewed recall grep flat, aliased Markdown files or keep a couple of flat editable files instead. Plain text is chosen for auditability and correctability. It's weak at multi-hop recall, and that tradeoff applies across the whole category, not to plain text alone.
- **"Multiple named agents" as a security boundary.** The framing is fine, but in at least one product the agents share one computer, one browser, and one set of logins, and its own docs concede that isn't a security boundary. Isolation has to be real at the credential and browser-profile layer (`docs/oauth-boundaries.md`). After adopting this, verify that the shared-browser scope hasn't drifted broader than intended.
- **Training on user interaction data.** Not applicable. Nothing these agents hold is fed back into a shared model. That's an advantage of local files, worth keeping.

## Related changes

- **Consolidation moved into the daily briefing jobs.** The most memory-sophisticated products run a daily background pass that edits the archive by generalizing, correcting with history preserved, and pruning, rather than only appending. Here, both scheduled briefing jobs got a mechanical sub-step: grep the latest daily log for a decision framework, named figures, or a multi-step conclusion not yet in `memory/entities/`, and promote it before composing the brief. See `docs/memory-conventions.md`, "Promote on the daily sweep."
- **Session checkpoint.** Durable knowledge surviving a restart was handled. In-flight session state wasn't. See `docs/session-continuity.md`.
