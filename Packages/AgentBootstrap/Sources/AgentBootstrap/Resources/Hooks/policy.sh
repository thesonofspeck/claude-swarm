#!/bin/sh
# Claude Code PreToolUse hook -> consult .claude/policy.json
#
# Stdin is the JSON event Claude Code passes to PreToolUse hooks. We read
# tool_name and tool_input.command (for Bash) and decide whether to
# auto-allow, deny, or fall through to "ask" (which surfaces to iOS).
#
# Output: a JSON object with hookSpecificOutput.permissionDecision and a
# reason. Claude Code then uses the decision in place of asking.

set -eu

POLICY_FILE="${CLAUDE_PROJECT_DIR:-$PWD}/.claude/policy.json"
INPUT="$(cat)"

if [ ! -f "$POLICY_FILE" ]; then
    # No policy installed -> let Claude Code's default ask flow run.
    exit 0
fi

python3 - "$POLICY_FILE" "$INPUT" <<'PY'
import json, re, sys

policy_path, raw = sys.argv[1], sys.argv[2]
with open(policy_path) as f:
    policy = json.load(f)

try:
    event = json.loads(raw)
except Exception:
    sys.exit(0)

tool_name = event.get("tool_name") or event.get("toolName") or ""
tool_input = event.get("tool_input") or event.get("toolInput") or {}

allow = set(policy.get("autoAllow", []))
ask = set(policy.get("alwaysAsk", []))
default = policy.get("default", "ask")

# 1. Always-ask wins over auto-allow when both contain the same tool.
if tool_name in ask:
    decision = "ask"
elif tool_name in allow:
    decision = "allow"
else:
    decision = default

# 2. Bash-specific destructive-pattern check. Even if Bash is in autoAllow,
#    a destructive pattern forces "ask".
if tool_name == "Bash" and decision == "allow":
    command = (tool_input.get("command") or "")
    for pattern in policy.get("destructiveBashPatterns", []):
        if re.search(pattern, command):
            decision = "ask"
            break

if decision == "allow":
    out = {
        "hookSpecificOutput": {
            "hookEventName": "PreToolUse",
            "permissionDecision": "allow",
            "permissionDecisionReason": "Auto-approved by .claude/policy.json"
        }
    }
    print(json.dumps(out))
elif decision == "deny":
    out = {
        "hookSpecificOutput": {
            "hookEventName": "PreToolUse",
            "permissionDecision": "deny",
            "permissionDecisionReason": "Denied by .claude/policy.json"
        }
    }
    print(json.dumps(out))
# else "ask" -> exit 0, Claude Code falls back to its own ask flow which
# fires the Notification hook -> reaches iOS.
PY
