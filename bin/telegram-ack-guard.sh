#!/bin/bash
# telegram-ack-guard.sh — PreToolUse hook (shared across all agents).
#
# Enforces the OPENING acknowledgement: if the most recent genuine user INBOUND
# arrived via Telegram and the agent has NOT yet acknowledged it this turn
# (a react OR a reply/edit through the Telegram tool), block the first
# substantive tool call and remind the agent to ack first ("step zero").
#
# Companion to telegram-reply-guard.sh (Stop hook), which enforces the CLOSING
# reply. Key difference: the closing guard requires a REPLY (a react is not
# enough); this opening guard accepts EITHER a react or a reply as the ack.
#
# Why: the closing reply is hook-enforced, but the opening ack never was, so on
# long, tool-heavy turns it silently dropped — the agent dove into the work and
# only the closing reply survived. This closes that gap structurally.
#
# Contract (PreToolUse): exit 0 = allow the tool call. exit 2 = block it and
# feed stderr back to the model. Fails OPEN on any error (never wedges work).
input=$(cat)
python3 - "$input" <<'PY'
import sys, json
try:
    data = json.loads(sys.argv[1])
except Exception:
    sys.exit(0)

tool = data.get("tool_name", "") or ""

# Always allow the acknowledgement tools themselves through (react/reply/edit),
# and ToolSearch — deferred Telegram tools must be loaded via ToolSearch before
# they can be called, so blocking it would make acking impossible.
if "telegram" in tool:
    sys.exit(0)
if tool in ("ToolSearch",):
    sys.exit(0)

path = data.get("transcript_path", "")
if not path:
    sys.exit(0)
try:
    lines = [json.loads(l) for l in open(path) if l.strip()]
except Exception:
    sys.exit(0)

def text_of(content):
    if isinstance(content, str):
        return content
    if isinstance(content, list):
        return " ".join(p.get("text", "") for p in content
                         if isinstance(p, dict) and p.get("type") == "text")
    return ""

def is_tool_result(content):
    return isinstance(content, list) and any(
        isinstance(p, dict) and p.get("type") == "tool_result" for p in content)

# Find the last GENUINE user inbound (a real message, not a tool_result echo).
last_idx = -1
last_is_tg = False
for i, o in enumerate(lines):
    m = o.get("message", {})
    if not isinstance(m, dict) or m.get("role") != "user":
        continue
    c = m.get("content")
    if is_tool_result(c):
        continue
    t = text_of(c)
    if not t.strip():
        continue
    last_idx = i
    last_is_tg = ('source="plugin:telegram:telegram"' in t)

if last_idx < 0 or not last_is_tg:
    sys.exit(0)

# Has the agent acknowledged since that inbound? A react OR reply/edit counts.
acked = False
for o in lines[last_idx + 1:]:
    m = o.get("message", {})
    if not isinstance(m, dict):
        continue
    c = m.get("content")
    if not isinstance(c, list):
        continue
    for p in c:
        if isinstance(p, dict) and p.get("type") == "tool_use":
            name = p.get("name", "")
            if "telegram" in name and (
                    "react" in name or "reply" in name or "edit_message" in name):
                acked = True

if not acked:
    sys.stderr.write(
        "BLOCK: the latest inbound arrived via Telegram and you have not "
        "acknowledged it yet. Fire the opening acknowledgement — a Telegram "
        "react (mcp__plugin_telegram_telegram__react) or a 1-2 word reply — "
        "BEFORE any other tool call. This is step zero of the turn.\n")
    sys.exit(2)
sys.exit(0)
PY
