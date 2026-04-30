#!/bin/sh
# Claude Code hook -> Claude Swarm notifier.
#
# Posts a JSON event to the Unix socket the app listens on. Reads the hook
# kind from the first arg and reads the hook payload (stdin, optional).
# Identifies the session via CLAUDE_SWARM_SESSION_ID set on session spawn.

set -eu

KIND="${1:-Notification}"
SESSION_ID="${CLAUDE_SWARM_SESSION_ID:-}"
SOCKET="${CLAUDE_SWARM_HOOK_SOCKET:-$HOME/Library/Application Support/ClaudeSwarm/hooks.sock}"

# Read optional message from stdin (Claude Code passes JSON; we forward as-is)
MESSAGE="$(cat 2>/dev/null || true)"
TS="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

PAYLOAD=$(cat <<EOF
{"kind":"$KIND","sessionId":"$SESSION_ID","projectPath":"$PWD","message":$(printf '%s' "$MESSAGE" | python3 -c 'import json,sys;print(json.dumps(sys.stdin.read()))'),"timestamp":"$TS"}
EOF
)

# Use python so we don't depend on `nc -U` flavor.
python3 - "$SOCKET" "$PAYLOAD" <<'PY'
import socket, sys
sock_path, payload = sys.argv[1], sys.argv[2]
try:
    s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    s.settimeout(2.0)
    s.connect(sock_path)
    s.sendall((payload + "\n").encode())
    s.close()
except OSError:
    sys.exit(0)
PY
