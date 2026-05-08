# Infrastructure

Two infrastructure choices that aren't strictly part of the framework but make a meaningful difference if you want this setup to be (a) remotely accessible from anywhere and (b) edited from your laptop while the agents run on a different machine.

Neither is required to start. Add them when the setup outgrows being on your daily-driver Mac.

## Tailscale — remote access to a headless Mac mini

The natural home for the agent fleet is a small machine that's always on, doesn't share a screen with your normal work, and stays plugged into power and ethernet. A Mac mini sitting in a closet does this well. The constraint: you'll occasionally need to actually look at the screen — to debug a stuck session, to grant a TCC permission, to install software, to attach to a tmux session and watch what an agent is doing in real time.

[Tailscale](https://tailscale.com) gives you a private network across all your devices over WireGuard. Once installed, every machine on your tailnet can reach every other by its short hostname (e.g., `mini.tail-XXXXX.ts.net` or just `mini`).

Two things become trivial with that:

**Screen sharing into the headless Mac mini.** macOS Screen Sharing works over the tailnet without exposing port 5900 to the public internet. From your laptop, open Finder → Go → Connect to Server → `vnc://mini.tail-XXXXX.ts.net`, sign in, and you're looking at the mini's screen. Useful for the occasional permission prompt or visual debug.

**SSH into the mini from anywhere.** `ssh you@mini` works from a coffee shop the same way it works from your living room. Useful for quick maintenance ("restart the atlas session", "tail the compass log") without needing to be on the same network.

### Setup, briefly

1. Install Tailscale on the Mac mini and on your daily-driver machine. Same Tailscale account.
2. Enable Magic DNS in the Tailscale admin console (so you can use short hostnames).
3. On the mini: System Settings → General → Sharing → enable Screen Sharing AND Remote Login.
4. From your daily driver: test `ssh you@<mini-tailnet-hostname>` and `vnc://<mini-tailnet-hostname>`.

That's the whole setup. A few one-time touches on each machine, then it just works.

### Why not iCloud / Apple Remote Desktop / port forwarding

- **iCloud screen sharing** works but is iCloud-account-coupled and laggier in practice.
- **Apple Remote Desktop** is the enterprise tool — overkill, costs money.
- **Port forwarding from your router** exposes ports to the public internet — a real attack surface and not worth it for personal use.

Tailscale's mental model is "private LAN that follows you" — that's the right primitive for this use case.

## Syncthing — shared file tree across machines

A second, distinct problem: you want to write the agent's `CLAUDE.md` from your laptop (where you have a real keyboard and good editor setup) but have the file land on the Mac mini where the agent is actually running. Or you want the chief-of-staff agent's research output to be readable from your laptop without SSHing every time.

[Syncthing](https://syncthing.net) is a peer-to-peer file-sync daemon that runs on each machine and continuously replicates a chosen directory tree. No cloud, no central server. Once configured, files written on either machine appear on the other within seconds.

The natural fit: a single workspace directory (e.g., `~/agents/shared/personal/` or a dedicated `~/agents-sync/`) that holds the artifacts you actively co-edit between machines. Skill packs, reference docs, in-progress essays, anything you'd want to be able to grab from your laptop without a separate "transfer" step.

### What to put in the synced tree (and what to keep out)

**Sync:**
- Skill packs (`shared/personal/skills/*`)
- Reference docs you're co-editing
- Long-form drafts (essays, blog posts, op-eds, talk scripts, etc.)
- Any document the agent on the mini and you-on-the-laptop both touch

**Don't sync:**
- `.git` directories (Syncthing isn't designed for them; you'll get conflicts)
- OAuth tokens / `.mcp/oauth/` (these are machine-scoped credentials)
- Agent runtime state (`.claude/`, `memory/` per-agent, `logs/`)
- The shared journal + delegation inbox (these need to be on the agent's machine where the agents are reading them; don't sync because consistency requirements are stricter than Syncthing provides)

The simple rule: sync the *artifacts you author* and the *reference content the agents read*. Don't sync the *runtime state* or *credentials*.

### Setup, briefly

1. Install Syncthing on each machine (`brew install syncthing` then enable the launchd plist that comes with it; or use the menu-bar app).
2. On both machines, open the Syncthing UI (http://localhost:8384) — they auto-launch in the browser.
3. Add each machine as a "remote device" via its device ID (visible in the UI).
4. On one machine, designate the workspace folder as a Syncthing share. Send the share to the other machine.
5. Accept on the other side, picking the local path where you want the synced copy to live.
6. Add a `.stignore` file in the shared dir to exclude `.git` and any sub-paths you don't want synced.

A reasonable starter `.stignore`:

```
.git
.git/**
node_modules
.DS_Store
.mcp/oauth
*.token
*.key
```

### Why not iCloud / Dropbox / Google Drive

- **iCloud Drive** has been historically unreliable for files actively being written by background processes; it can stall, conflict, or rewrite-loop with macOS file events. Not worth the risk for the agent fleet.
- **Dropbox / Google Drive** add a cloud middleman for data that doesn't need one. The agent's working files don't benefit from being on a vendor's server.
- **rsync over cron** works but isn't continuous; you wait for the next sync interval, and conflicts are silent.

Syncthing's continuous, peer-to-peer model is the right shape — your data, your machines, near-real-time, no third party.

## Putting them together

The combined pattern:
- Mac mini in a closet, always on, runs the agent fleet (`tmux` sessions supervised by `launchd`)
- Daily driver (your laptop) where you do active editing + occasional visual debugging
- Tailscale for SSH + screen sharing into the mini from anywhere
- Syncthing for the shared workspace files (skill packs, drafts, reference docs)
- Telegram is the always-on conversational surface — agents talk to you regardless of which machine you're on, regardless of which network you're on

This combination is what makes "I have a personal AI team" actually feel like having a team rather than feeling like babysitting a process. The team is on the mini; you're wherever you are; the messaging surface follows you.

## Anti-patterns

**Running agents on your daily driver.** It works at first. Then your laptop dies, runs hot, you take it on a trip, an OS update reboots it without you noticing — and the agent fleet goes down with it. Move them to a dedicated machine.

**Exposing ports to the public internet for remote access.** Even with strong passwords, the constant scan/probe traffic is noise + risk. Use Tailscale instead.

**Syncing the entire workspace tree.** You'll fight constant conflicts on `.git`, on agent memory writes, on log rotation. Sync only the artifact + reference content layer.

**Skipping these and "just SSHing when I need to."** It works until you realize 80% of your agent-related editing happens at your laptop and you don't want to switch contexts every time. Set up Tailscale + Syncthing once; reap the benefit forever.
