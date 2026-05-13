# Delegation pattern

When one agent hands work to another, the handoff happens through a markdown file in a shared inbox. The recipient processes the file, appends a `# Response` section, and moves the file to an archive. That's the whole protocol.

This is the load-bearing primitive that makes a multi-agent setup tractable. Get it right and every other piece falls into place.

## Why files

Three properties that matter, and one corollary.

**Reviewable.** Every delegation is a markdown file you can `cat`. Every response is appended to it. The trail is just a folder. When something goes wrong, you don't reconstruct what was sent — you read it.

**Async-native.** The inbox doesn't care whether the recipient is awake. The orchestrator drops the file and moves on. The recipient picks it up when its session is ready. No timing coupling, no queue infrastructure, no message broker.

**Recoverable.** If a session dies mid-task, no in-flight state is lost. The file is still in the inbox. The recipient picks up where it left off on next wake.

The corollary: every delegation IS its own audit log, retrospective, and replay. You can reconstruct what the system did at any point by reading the archive.

## Why launchd one-shot (not subshell)

This is the non-obvious part.

The naive way to wake a specialist is to spawn it from the orchestrator's shell:

```bash
# DON'T DO THIS
(cd ~/agents/specialist && claude -p "check inbox")
```

This breaks. The subshell-spawned child inherits the parent's process group at the kernel level. Some MCP server transports (notably the Telegram channels-mode plugin running under bun) interpret the spawn-time process tree perturbation as transport-unhealthy and recycle. That kills the parent's MCP-to-claude pipe, which means the parent loses its messaging surface.

The fix is to make the spawn a child of `PID 1` instead of the parent. On macOS, that means routing through `launchd`:

```bash
LABEL=$(./bin/submit-delegation.sh specialist /tmp/wake-prompt.txt)
./bin/wait-delegation.sh "$LABEL"
./bin/cleanup-delegation.sh "$LABEL"
```

The helper writes a one-shot plist, bootstraps it via `launchctl bootstrap`, returns the unique label. The job runs as a `launchd`-managed process with its own session, fully decoupled from the orchestrator's process tree.

Why this matters in practice: the failure mode of the subshell pattern is silent — the orchestrator's MCP transport recycles, the user's messages stop arriving in the orchestrator's session, and there's no error in any one place that points at the spawn as the cause. The launchd pattern eliminates the failure mode by construction.

## File format

```
shared/delegations/inbox/<timestamp>-<from>-<to>-<slug>.md
```

Where:
- `<timestamp>` is `YYYY-MM-DDTHH-MM-SS` (ISO-ish, file-system-safe). Lets you sort delegations chronologically.
- `<from>` is the orchestrator agent name
- `<to>` is the specialist agent name
- `<slug>` is a short kebab-case hint at the task

Frontmatter:

```yaml
---
from: <orchestrator>
to: <specialist>
created: <timestamp>
status: open | in-progress | rfc1 | complete
priority: high | normal | low
sla: <human-readable expectation>
deliverable: <one-line summary of what's being asked>
---
```

Body sections (recommended, not enforced):

1. **Task** — what's being asked
2. **Context** — what the specialist needs to know
3. **Constraints** — hard rules, non-negotiables, things to NOT do
4. **Deliverable** — what artifact + format + where it lives when done
5. **Reference materials** — paths to relevant files

When the specialist finishes, it appends a `# Response` section to the same file, then moves the file to `shared/delegations/archive/`.

## Response section

```markdown
---

# Response

**Status:** complete | partial | blocked

**Output:** <path-to-artifact>

**Summary:** <2-3 sentences>

**What landed well:** <bullets>

**Sections to look at first:** <bullets — what's least confident>

**Concerns / flags:** <bullets — anything the orchestrator should know>
```

Keep it short. The orchestrator (or the user) should be able to read the response in 30 seconds and decide whether to dig into the artifact or move on.

## Completion ping (return path)

The Response section gives the orchestrator what to read. The completion ping tells the orchestrator there's something to read.

Without it, completion is passive — the orchestrator discovers the response on its next file-modified system reminder, its next interactive turn, or its next inbox scan. That can be hours. If the orchestrator is mid-conversation and the specialist's work matters to the next step, the gap is felt.

The fix is a small active surface: a dedicated directory the orchestrator scans on each cycle, where specialists drop a one-line ping when they finish.

### Convention

```
shared/orchestrator-inbox/<timestamp>-<from>-<slug>.md
```

Frontmatter:

```yaml
---
from: <specialist>
completed_at: <timestamp>
delegation_id: <original delegation filename without .md>
archive_file: shared/delegations/archive/<original delegation filename>
---
```

Body: one sentence summarizing what landed and the headline finding. Just enough that the orchestrator can decide whether to read the full response now or queue it for later.

Naming the directory `orchestrator-inbox` is the generic convention; in practice it's typically named after the specific orchestrator (e.g., `atlas-inbox`) since each orchestrator drains its own queue.

### Closeout flow

After the specialist appends the Response section and moves the file to archive, it also writes the ping:

1. Process the task, write the artifact.
2. Append the `# Response` section to the delegation file.
3. Move the file from `inbox/` to `archive/`.
4. Append one line to `shared/journal.md`.
5. **Write the ping file to `shared/orchestrator-inbox/`** (~5 lines, takes a second).

The orchestrator's responsibilities:

- Scan the orchestrator-inbox at the start of each session and at sweep intervals.
- Read the ping summary; surface to the user if relevant.
- Move processed pings to `orchestrator-inbox/processed/` so the inbox shows only fresh work.

### Why a separate file (not just journal grep)

A naive alternative is "the orchestrator scans recent journal entries for `[specialist] complete` lines." Two problems:

- The journal is append-only and lossless — every line stays forever. The orchestrator-inbox is a stack you drain.
- Journal entries are unstructured. The ping is parseable (frontmatter) and consumable in seconds.

A dedicated dir is the operationally cheap way to say *here's a thing to look at, and once you've looked, move it*.

### When the ping has nothing notable

Even if the specialist's response doesn't surface anything that needs the orchestrator's attention (e.g., a routine sweep that produced no surprises), still write the ping. It's the heartbeat that says the delegation actually ran. Pings without notable findings are summarized as *"no surprises, see archive if needed."*

## RFC flow

If the specialist needs clarification before it can finish, it doesn't pick a direction and apologize later. It returns the file with `-rfc1` suffix and a `## Open questions` section listing what it needs to know.

```
inbox/2026-05-07T16-05-00-atlas-writer-essay-v2-rfc1.md
```

The orchestrator (or the user) answers the questions inline, bumps to `-rfc1-answered`, moves the file back to inbox, and re-fires the launchd one-shot to wake the specialist.

The point of RFC isn't friction. It's that an under-specified delegation produces a wrong artifact, and a wrong artifact costs more to throw away than the round-trip cost of asking.

## Helpers

Three scripts in `bin/`:

**`submit-delegation.sh <target> <prompt-file> [flags]`**
Generates a unique launchd plist label, writes the plist, bootstraps it, returns the label. Optional flags:
- `--add-dir <path>` — additional directory the spawned session can access
- `--mcp-config <path>` — explicit MCP config (otherwise inherits `<target>/.mcp.json`, or the per-target default from the case block — see "Channels-mode targets" below)
- `--strict-mcp-config` — pair with `--mcp-config` to lock down MCP loading
- `--allowed-tools "<list>"` — limit tool surface

`--dangerously-skip-permissions` is built in — required for the spawned session to actually write files without interactive permission grants that won't fire in `-p` mode.

**`wait-delegation.sh <label>`**
Polls launchctl for the job's exit. Blocks until done. Returns the log path + exit code.

**`cleanup-delegation.sh <label> [--keep-logs]`**
Tears down the plist + removes generated artifacts. Default removes logs; `--keep-logs` preserves output for inspection.

All three are POSIX shell scripts. No Python, no Node, no dependencies beyond what's already on macOS.

## Channels-mode targets and the worker MCP gotcha

If your target agent runs in `--channels` mode (i.e., it has a Telegram bot polling via the channels plugin), naive delegation will silently break the target's Telegram connection. This is the second non-obvious failure mode after the subshell issue, and the symptoms look unrelated to delegation.

### The bug

When the worker claude is spawned without an explicit `--mcp-config`, it loads the target's MCP setup. That setup includes the Telegram channels plugin (which spawns a `bun` process polling the bot). Telegram's API enforces a single `getUpdates` consumer per bot token, so when the worker's bun starts polling, the target's bun has to lose. The plugin's stale-poller-detection logic SIGTERMs the older bun. Worker exits, its bun dies too. Net result: the target has no Telegram channel until you restart its claude session.

The pathological pattern shows up in the plugin's stderr log:
```
telegram channel: polling as @your_bot
telegram channel: replacing stale poller pid=XXXX
telegram channel: shutting down
```
…repeated dozens of times across delegation events, with the target's `bot.pid` file going missing each time.

### The fix

Spawn the worker with a curated `--mcp-config` that includes everything the target needs at delegation time EXCEPT the telegram plugin. Pair with `--strict-mcp-config` so nothing else sneaks in.

The bundled `submit-delegation.sh` has a case block (right after option parsing) where you map per-target curated configs:

```sh
if [ -z "$MCP_CONFIG" ]; then
    case "$TARGET" in
        my-channels-agent)
            MCP_CONFIG="${WORKSPACE_ROOT}/.delegations/worker-mcp-my-channels-agent.json"
            STRICT_MCP=1
            ;;
        *) ;;
    esac
fi
```

Use `templates/worker-mcp.json.template` as the starting shape — drop in every MCP server from the target's `.mcp.json`, leave telegram out. One curated config per channels-mode target.

### Targets that don't need this

If the target agent is terminal-only (no `--channels` flag, no telegram bot), the default behavior is correct and the case block doesn't need an entry. Symptom check: if `pgrep -f "bun.*telegram"` returns nothing for the target, you're safe.

## Anti-patterns

**Spawning specialists from a subshell.** Documented above. This is the failure mode that motivated the launchd pattern.

**Skipping the file step ("just call the API directly").** You lose async-native, you lose the audit trail, and you couple the orchestrator's session lifetime to the specialist's. Don't.

**Not writing a Response section.** The artifact alone is not the deliverable. The Response is what tells the orchestrator (or the user) whether the artifact landed. Specialists that skip this step force the orchestrator to read the artifact end-to-end on every delegation, which doesn't scale.

**Mixing "wake the agent" with "give the agent an instruction."** The wake prompt should be `"check your delegation inbox; new file is at <path>; process per its instructions"`. NOT the full task brief inline. The brief is in the file. The wake prompt is just the trigger.

**Forgetting to archive.** Files left in inbox after completion clutter the queue and lose the "what's actually open right now" signal. Archive is part of the closeout — make it a hard requirement in the delegation template.
