# Claude Swarm

A native macOS app for running and managing many Claude Code sessions across
projects. Each task gets its own git worktree + branch, an embedded `claude`
CLI in a real terminal, plus integrated views of files, diffs, history, the
related Wrike task, and the resulting GitHub PR.

## Status

v0.1 in progress on branch `claude/claude-session-manager-app-zvkzj`. Skeleton
scaffolding only — modules and types are stubbed; nothing is wired up yet.

## Repo layout

```
ClaudeSwarm.xcworkspace          (created in Xcode)
App/                             SwiftUI app target
  ClaudeSwarmApp.swift           @main entry point
  Views/                         RootSplitView, tab views, inspector
  Resources/
    Agents/                      6 default subagent templates
    Hooks/                       Notification/Stop hook script templates
    Templates/                   .mcp.json template, .claude/settings.json template
Packages/
  AppCore/                       Cross-cutting models, view models, DI
  SessionCore/                   PTY spawn, lifecycle, transcript recorder
  TerminalUI/                    SwiftTerm NSViewRepresentable
  GitKit/                        Worktree, diff, history (shells out to git)
  DiffViewer/                    Unified-diff SwiftUI renderer
  WrikeKit/                      Wrike REST client
  GitHubKit/                     GitHub REST + GraphQL client
  PersistenceKit/                GRDB schema + repositories
  KeychainKit/                   SecItem wrapper
  MemoryService/                 In-app MCP server, namespaced semantic memory
  NotificationCenter/            Hook socket server + UNUserNotifications
  AgentBootstrap/                Per-project install of agents/hooks/.mcp.json
```

## Building

This is an Xcode project. From a Mac:

```sh
open ClaudeSwarm.xcworkspace
```

The workspace doesn't exist yet — see `docs/setup.md` once it's added. For
now, each `Packages/*` directory is a standalone SwiftPM package and can be
opened individually in Xcode (`File > Open` the package directory).

## Default agent team

On project registration, six subagents are written into `<repo>/.claude/agents/`:

- `team-lead` — orchestrator, decomposes work and delegates via the Task tool
- `ux-designer` — flows, wireframes, copy
- `systems-architect` — module/data/API design
- `engineer` — implementation
- `qe` — tests, edge cases
- `reviewer` — final pass before PR

## Memory

Every session gets a stdio MCP connection to the bundled memory server,
exposing `memory_write`, `memory_search`, `memory_get`, `memory_list`,
`memory_delete`. Namespaces: `global`, `project:<id>`, `session:<id>`.

## Notifications

Sessions waiting for input surface as a sidebar dot, dock badge, and macOS
notification — driven by Claude Code's `Notification` and `Stop` hooks
piping events to a Unix domain socket the app listens on.

## Plan

The full implementation plan lives at
`/root/.claude/plans/i-want-to-build-mossy-goblet.md` (developer-local).
