# The learning loop

An assistant that drafts things produces a lot of output that is never used verbatim. The user edits the email, ignores the recommendation, or does something else entirely. **The edit is the signal**, and by default it evaporates — the next session starts clean and makes the same mistake.

This is the pattern that closes that loop: harvest what the agent suggested, find what the user actually did, record the delta, and promote a delta into a rule once it has happened more than once.

## Why it isn't just "ask for feedback"

Users don't give feedback on 90% of drafts. They silently fix them and move on, because fixing is faster than explaining. The fix *is* the feedback, and it is already sitting in the sent folder.

## The three pieces

### 1. Harvest — mechanical

A script that reads the day's conversation across **every interface the user can reach the agent on** — chat channel, terminal, web widget — and flags messages that look like a draft or a recommendation, i.e. something with a real-world outcome worth checking.

Two exclusions matter, and both were bugs before they were rules:

- **Scheduled job prompts are not the user talking.** If cron wakes the agent with a prompt, that prompt is not an instruction from the user, and counting it means the agent grades itself against its own scheduler. Filter on whatever distinguishes an automated run from an interactive one — session entrypoint, a marker in the prompt, the absence of a channel tag.
- **On a channel turn, the tool call is the message.** The assistant's transcript text on those turns is narration the user never sees. Count it and you treat the agent's own thinking as if it were a suggestion. Count assistant text only on turns where the terminal *is* the channel.

### 2. Ground truth — wherever the artifact landed

In rough order of yield:

- **Sent mail.** Highest-yield source for anything communications-shaped, and the reason read access to the user's sent folder is worth more than access to their inbox.
- **The task or CRM system.** Row state, and whether prose the agent proposed survived contact.
- **Files and documents.** The final version of something the agent drafted.
- **The conversation itself.** Users often paste their own version back — *"what about just dropping X"*. That is the cleanest signal available, because it is explicit.

### 3. Judgement — the part that stays with the model

The script harvests; a **skill** does the reasoning. Classify each delta:

| Delta | What it means | Where the lesson goes |
|---|---|---|
| **Edited** — used, but changed | Craft. Voice, length, register. | The writing-preferences file |
| **Replaced** — user did something materially different | Judgement. The agent solved the wrong problem. | A `feedback_*` memory |
| **Dropped** — never happened | Ambiguous. Wrong, or simply not a priority. | Note only; never promote alone |

Diff *meaning*, not words. "They cut a sentence" is not a finding. "They cut the sentence explaining why, because they don't explain themselves to people who already know" is.

## The promotion rule

Record every delta with a **pattern tag**. Count the tags. **A tag that recurs twice or more has earned a rule; a single instance has not.**

One edit is a person writing in their own voice, which they are entitled to do. Encoding it as a rule is how an assistant becomes annoying. Two independent instances of the same delta is a pattern.

Route by kind: writing lessons into the preferences file the agent already reads, behavioural lessons into memory, and **anything that would change the agent's own operating contract gets proposed to the user rather than written silently.**

## The rule that governs all of it

**No signal is a valid, common, and final answer.**

Most of what a user does leaves nothing the agent can observe — phone calls, in-person conversations, work done from an account the agent cannot read. When there is no artifact, record *no signal* and stop. Do not infer, and never read silence as rejection.

This matters more over time, not less. As an assistant becomes useful its user starts routing work through channels it cannot see, and the fraction of dark outcomes goes **up**.

## Failure modes

- **Manufacturing findings.** Most days contain no lesson. An empty ledger entry is a correct outcome.
- **Encoding one-offs.** See the promotion rule. Two, not one.
- **Reading "dropped" as rejection.** The weakest evidence there is.
- **Grading the user.** This measures the agent's suggestions, not the user's execution. A record that evaluates what they did is out of bounds, and if they ever read the ledger it should read as an agent critiquing itself.
- **Re-deriving tags.** Before writing a new pattern tag, read the existing ones. A tag used once is invisible to the promotion step, so a synonym is the same as a discard.

## Scheduling

Run it once a day, after the working day has produced artifacts to compare against. If that lands inside quiet hours, the job must not notify — findings surface in the next scheduled briefing. A learning loop that wakes someone at 21:15 to say it learned something has failed at the thing it is trying to learn.
