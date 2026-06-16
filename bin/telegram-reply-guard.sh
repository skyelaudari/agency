#!/bin/bash
# telegram-reply-guard.sh — Stop hook (shared across all agents).
#
# Blocks ending a turn if the most recent genuine user INBOUND arrived via
# Telegram but the agent did not answer through the Telegram REPLY/edit tool.
#
# COURTESY EXCEPTION: if the inbound is a pure acknowledgement ("thanks", "ok",
# "got it", "sounds good", an emoji, etc. — short, no question, no request) and
# the agent fired a REACT this turn, that's enough — a react is the natural
# close to a thank-you and forcing "you're welcome!" is performative noise. For
# anything substantive (a question, a request, real content), a real reply is
# still required (a react alone is NOT enough).
#
# Companion to telegram-ack-guard.sh (PreToolUse, opening acknowledgement).
# Contract: exit 0 = allow stop. exit 2 = block + stderr fed back to the model.
# Fails OPEN on any error.
input=$(cat)
python3 - "$input" <<'PY'
import sys, json, re
try:
    data = json.loads(sys.argv[1])
except Exception:
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

# Last GENUINE user inbound (a real message, not a tool_result echo).
last_idx, last_text, last_is_tg = -1, "", False
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
    last_idx, last_text = i, t
    last_is_tg = ('source="plugin:telegram:telegram"' in t)

if last_idx < 0 or not last_is_tg:
    sys.exit(0)

# Did the agent reply (or edit) — and/or react — since that inbound?
replied = reacted = False
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
            if "telegram" in name:
                if "reply" in name or "edit_message" in name:
                    replied = True
                elif "react" in name:
                    reacted = True

if replied:
    sys.exit(0)

# Courtesy exception: pure-acknowledgement inbound + a react this turn = enough.
inner = re.sub(r"<channel[^>]*>", "", last_text)
inner = inner.replace("</channel>", "")
words = re.findall(r"[a-zA-Z']+", inner.lower())
COURTESY = {"thanks", "thank", "you", "thx", "ty", "ok", "okay", "k", "got",
            "it", "sounds", "good", "great", "perfect", "cool", "will", "do",
            "nice", "awesome", "done", "np", "no", "problem", "appreciate",
            "yep", "yup", "sure", "cheers", "ditto", "roger"}
has_question = "?" in inner
is_courtesy = (len(words) <= 4 and not has_question
               and all(w in COURTESY for w in words))

if is_courtesy and reacted:
    sys.exit(0)

sys.stderr.write(
    "BLOCK: the last inbound arrived via Telegram, but you have not called the "
    "Telegram reply tool (mcp__plugin_telegram_telegram__reply) this turn. A "
    "react/emoji is NOT a reply (unless the inbound was a pure thanks/ack and "
    "you reacted). Send your text answer through the Telegram reply tool before "
    "stopping.\n")
sys.exit(2)
PY
