# Telegram acknowledgement guards

Two complementary hooks that enforce the agent's Telegram conversational
contract: **acknowledge every inbound on receipt, and always close with a real
reply.** Behavioral reminders in the system prompt alone did not hold on long,
tool-heavy turns — the agent would dive into the work and the acknowledgement
would silently drop. These hooks close that gap structurally.

## The contract they enforce

1. **Opening acknowledgement (step zero).** The moment a Telegram inbound
   arrives, the agent fires a quick ack — an emoji **react** *or* a 1–2 word
   reply — before doing the work. This is the heartbeat that tells the user the
   pipes are working while a long turn runs.
2. **Closing reply.** Before the turn ends, the agent must answer through the
   Telegram **reply** tool (a react is *not* a reply; a terminal-transcript
   answer is not a Telegram reply).

## The two hooks

| Hook | Event | Enforces | Ack that satisfies it |
|---|---|---|---|
| `bin/telegram-ack-guard.sh` | `PreToolUse` | Opening acknowledgement | react **or** reply/edit |
| `bin/telegram-reply-guard.sh` | `Stop` | Closing reply | reply/edit — **or** a react when the inbound is a pure courtesy message |

### Courtesy exception (closing guard)

A bare "thanks" / "ok" / "got it" doesn't need a typed reply — a react is the
natural close, and forcing "you're welcome!" is performative noise. So the
closing guard accepts a **react alone** when the inbound is a *pure
acknowledgement*: short (≤4 words), no `?`, and every word is in a courtesy
allowlist (thanks, ok, got it, sounds good, etc.). Anything substantive — a
question, a request, mixed content like "thanks, also send Y" — still requires a
real reply (a react is not enough). The check is deliberately conservative: when
in doubt it requires the reply, so the failure mode is an extra reply, never a
dropped one.

**`telegram-ack-guard.sh` (PreToolUse):** if the most recent genuine user
inbound arrived via Telegram and the agent has not yet acknowledged it this
turn, it blocks the first *substantive* tool call and reminds the agent to ack
first. It allows `ToolSearch` and any Telegram tool through unconditionally —
otherwise the agent could not load/call the react tool to satisfy it.

**`telegram-reply-guard.sh` (Stop):** if the most recent inbound was Telegram
and no reply/edit tool fired this turn, it blocks the stop so the agent must
answer through Telegram before ending.

Both **fail open** — any parse error or missing transcript exits 0 (allow), so a
hook bug can never wedge the agent. Both detect a "genuine inbound" by skipping
`tool_result` echoes and matching `source="plugin:telegram:telegram"` on the
last real user message, so terminal-origin turns are unaffected.

## Wiring (per agent `.claude/settings.json`)

Point every Telegram-enabled agent at the shared scripts (one canonical copy,
e.g. under a shared `hooks/` directory):

```json
{
  "hooks": {
    "PreToolUse": [
      { "hooks": [ { "type": "command", "command": "bash /ABS/PATH/hooks/telegram-ack-guard.sh" } ] }
    ],
    "Stop": [
      { "hooks": [ { "type": "command", "command": "bash /ABS/PATH/hooks/telegram-reply-guard.sh" } ] }
    ]
  }
}
```

No `matcher` is needed — `telegram-ack-guard.sh` self-filters (it allows
`ToolSearch` and Telegram tools, and no-ops on non-Telegram turns). Settings are
read once at session start, so restart the agent session after wiring.

## Rationale

The closing reply was hook-enforced first; the opening ack was not, so it
dropped exactly on the turns where it mattered most (long research/drafting
turns that leave the user waiting). Enforcing the opening ack at `PreToolUse` —
where "step zero" actually happens — makes the heartbeat structural rather than
a matter of the model remembering.
