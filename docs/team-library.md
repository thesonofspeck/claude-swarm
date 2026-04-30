# Team library

A team library is a single source of Claude Code customization that every
teammate's Mac pulls from: agents, skills, slash commands, MCP servers,
hooks, and a CLAUDE.md template. Same setup, zero config drift.

## Layout

A team library is just a directory with one manifest at the root:

```
swarm-library.json          # the manifest
agents/
  team-lead.md              # subagent files
  ux-designer.md
  ...
skills/
  release-checklist.md
  ...
commands/
  review.md                 # slash command files
  ship.md
  ...
mcp/
  github.json               # one entry per MCP server (merged into .mcp.json)
  filesystem.json
hooks/
  pre-edit-format.json      # one entry per hook (merged into settings.json)
claude-md/
  default.md                # CLAUDE.md template(s)
```

## Manifest schema

`swarm-library.json`:

```json
{
  "version": 1,
  "name": "Acme Engineering",
  "description": "Shared Claude Code config",
  "items": [
    {
      "id": "team-lead",
      "kind": "agent",
      "name": "Team Lead",
      "description": "Orchestrator for multi-step tasks",
      "path": "agents/team-lead.md",
      "version": "1.2.0",
      "tags": ["orchestrator", "default"]
    },
    {
      "id": "github",
      "kind": "mcp",
      "name": "GitHub MCP",
      "description": "Read/write GitHub via the official server",
      "path": "mcp/github.json",
      "version": "0.4.0",
      "tags": ["github"]
    },
    {
      "id": "review",
      "kind": "command",
      "name": "/review",
      "description": "Run a self-review pass before opening a PR",
      "path": "commands/review.md",
      "version": "1.0.0"
    }
  ]
}
```

`kind` is one of: `agent`, `skill`, `command`, `mcp`, `hook`, `claudeMd`.

## File contents per kind

- **agent / skill / command / claudeMd** — Markdown, copied verbatim
  into `<repo>/.claude/agents/` (etc.) or `<repo>/CLAUDE.md`.
- **mcp** — JSON containing a single entry that gets deep-merged into the
  project's `.mcp.json` `mcpServers` map under the item's `id`. Example:
  ```json
  {
    "command": "npx",
    "args": ["-y", "@modelcontextprotocol/server-github"],
    "env": { "GITHUB_TOKEN": "${GITHUB_TOKEN}" }
  }
  ```
- **hook** — JSON `{ "<EventName>": [<hookEntry>, …] }` merged into
  `.claude/settings.json` `hooks`. Example:
  ```json
  {
    "PostToolUse": [
      {
        "matcher": "Edit|Write",
        "hooks": [{ "type": "command", "command": "/usr/local/bin/pre-edit-format.sh" }]
      }
    ]
  }
  ```

## Configure on the Mac

In Claude Swarm: open any project's **Library** tab → gearshape →
**Team library**. Pick **Git repository** and paste the URL (or **Local
folder** for an internal share).

Behind the scenes the app does:

- **Git**: shallow-clones into
  `~/Library/Application Support/ClaudeSwarm/library-cache/<slug>/`
  on first use; subsequent refreshes do `git fetch --depth 1` +
  `git reset --hard origin/<branch>`.
- **Local**: reads in place — no copying, no cache.

The Library tab then shows three layers — built-in agents, team items,
and per-project items — with **Install** / **Uninstall** / **Sync**
controls per row. The "Sync" pill appears when the team source-file
hash differs from what's recorded in the project's
`.claude/swarm-library.lock.json`.

## Quick start (build a new team library)

```sh
# in your team-config repo
cat > swarm-library.json <<'EOF'
{
  "version": 1,
  "name": "Acme",
  "items": [
    { "id": "team-lead", "kind": "agent", "name": "Team Lead",
      "description": "Orchestrator", "path": "agents/team-lead.md",
      "version": "1.0.0" }
  ]
}
EOF
mkdir agents
cp ~/your-existing-team-lead.md agents/team-lead.md
git init && git add . && git commit -m "Initial library"
git remote add origin git@github.com:acme/swarm-library.git
git push -u origin main
```

Each teammate then opens Claude Swarm → Library → gearshape → Git, paste
`git@github.com:acme/swarm-library.git`, save.
