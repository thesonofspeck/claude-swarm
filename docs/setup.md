# Claude Swarm — setup

This is the v0.1 skeleton. The Xcode workspace is not yet generated; you
finish that step on a Mac.

## Prerequisites

- macOS 14 (Sonoma) or newer
- Xcode 15+
- `git` 2.40+ (for `worktree` features used here)
- The `claude` CLI on PATH (`which claude` from a terminal)
- (Optional) `gh` CLI logged in, so the app can reuse `gh auth token`

## Generating the Xcode workspace

The repo ships as a SwiftPM workspace (one app target + 12 local packages).
Create the Xcode workspace once:

1. From a Mac terminal in the repo root:
   ```sh
   open -a Xcode .
   ```
   Xcode will detect the SwiftPM packages.
2. `File > New > Workspace…`, save it as `ClaudeSwarm.xcworkspace` in the
   repo root.
3. `File > Add Files to "ClaudeSwarm"…` and add both `App/` and each
   `Packages/*/` directory.
4. Add a new macOS App target inside `App/`:
   - Product Name: `ClaudeSwarm`
   - Interface: SwiftUI
   - Language: Swift
   - Source files in `App/` and `App/Views/`
   - Link these package products: `AppCore`, `PersistenceKit`, `GitKit`,
     `DiffViewer`, `TerminalUI`, `SessionCore`,
     `ClaudeSwarmNotifications`, `AgentBootstrap`
5. Capabilities:
   - Hardened Runtime: ON
   - App Sandbox: OFF for v0.1 (we spawn child processes and touch arbitrary
     git checkouts; sandboxing is its own milestone)
   - User Notifications: enable for dock badge + alerts

## First run

1. Build & run from Xcode.
2. The app creates `~/Library/Application Support/ClaudeSwarm/` on launch.
3. Add a project: provide a local checkout path, default base branch (e.g.
   `main`), and the Wrike folder ID it maps to.
4. Connect Wrike & GitHub from `Settings…` (PAT for Wrike; GitHub will
   reuse `gh auth token` if found, otherwise prompts for a PAT).
5. Pick a task in the Tasks tab, click **Start session**.
6. Watch your worktree, branch, and `claude` session appear in the sidebar.

## Memory MCP server

The memory server runs as part of the app (see `MemoryService/MCPServer.swift`).
For each session, `AgentBootstrap` writes a `.mcp.json` into the worktree so
`claude` connects to the server over stdio.

To run the server standalone for testing:
```sh
swift run swarm-memory-mcp serve --stdio
```
(Add a `swarm-memory-mcp` executable target in Xcode that wraps
`MemoryService.MCPServer`.)

## Hook script

`Resources/Hooks/notify.sh` is installed into each project's
`.claude/settings.json` as `Notification` and `Stop` hooks. It posts JSON
events to `~/Library/Application Support/ClaudeSwarm/hooks.sock`, which the
app listens on via `HookSocketServer`.

## Status check

A v0.1 smoke test:

- [ ] Add a project, start a session, see worktree under `~/Library/Application Support/ClaudeSwarm/worktrees/`
- [ ] Embedded terminal runs `claude`, agents folder populated in repo
- [ ] Stop typing — yellow dot + dock badge + macOS notification
- [ ] Diff tab shows working-tree changes; History tab shows commits
- [ ] Open PR pushes branch and creates GitHub PR with seeded title/body
- [ ] Memory tab shows entries written by team-lead / engineer

## Known stubs

These are placeholders the v0.1 implementer must fill in on Mac:

- `App/Views/SidebarView.swift` — the new-session button is wired to nothing
- `App/Views/DetailView.swift` — Files / PR / Tasks / Memory / Agents tabs are placeholders
- `MemoryService/MCPServer.swift` — line-delimited JSON-RPC; verify against
  Claude Code's MCP transport when wiring up
- `TerminalUI/PTYTerminalView.swift` — color palette tuning, command-key passthrough,
  scrollback persistence
