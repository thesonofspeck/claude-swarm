# Claude Swarm — setup

This is v0.1. The Xcode workspace is not committed; you generate it once on
your Mac. After that, normal Xcode build/run.

## Prerequisites

- macOS 26 (Tahoe) or newer
- Xcode 26+ with command-line tools (`xcode-select --install`)
- `git` 2.40+ (for `worktree` features)
- The `claude` CLI on PATH (`which claude`)
- The `gh` CLI installed and logged in (`gh auth login`) — used for **all**
  GitHub operations
- Python 3 — used by the bundled hook script for portable Unix-socket writes

## One-time workspace setup

The repo ships as a SwiftPM workspace: one Xcode app target plus 12 local
packages. The first time:

1. From the repo root:
   ```sh
   open -a Xcode .
   ```
2. **File → New → Workspace…**, save as `ClaudeSwarm.xcworkspace` in the repo
   root.
3. **File → Add Files to "ClaudeSwarm"…** — add `App/` and each
   `Packages/*/` directory.
4. Add a new macOS **App** target (`ClaudeSwarm`):
   - Interface: SwiftUI
   - Source files: everything under `App/`
   - Link package products: `AppCore`, `PersistenceKit`, `GitKit`,
     `DiffViewer`, `TerminalUI`, `SessionCore`, `ClaudeSwarmNotifications`,
     `AgentBootstrap`, `GitHubKit`, `WrikeKit`, `KeychainKit`, `MemoryService`
5. Capabilities on the app target:
   - **Hardened Runtime**: ON
   - **App Sandbox**: OFF for v0.1 (we spawn child processes and touch
     arbitrary git checkouts; sandboxing is a separate project)
   - **User Notifications**: enabled (badge + alerts)
6. Build & run. The app creates `~/Library/Application Support/ClaudeSwarm/`
   on first launch.

## First run

1. **Onboarding sheet** appears — connect Wrike (optional PAT) and confirm
   `gh auth status`.
2. **Add a project** from the sidebar:
   - Pick a local repo via the file picker
   - Set default base branch (default `main`)
   - Optionally map to a Wrike folder ID
3. The app installs `.claude/agents/*.md` (six default subagents),
   `.claude/skills/*.md` (memory + drafters), `.claude/settings.json`
   (Notification + Stop hooks plus memory file permissions), and an empty
   `.mcp.json` into the project. Existing files are merged, not overwritten.
4. Open the **Tasks** tab → click a task → **Start session**.
5. The app creates a worktree under
   `~/Library/Application Support/ClaudeSwarm/worktrees/<repo>/<task-slug>/`,
   spawns `claude` there as the `team-lead` agent, and the embedded terminal
   appears in the **Terminal** tab.

## What the tabs do

- **Terminal** — the live `claude` session for this worktree
- **Files** — virtualized worktree tree with file preview (1 MiB cap)
- **Diff** — working-tree changes vs. base, side-by-side file list
- **History** — `git log` with per-commit diff
- **PR** — push branch + `gh pr create`, plus inline checks and review
  comments from `gh pr checks` / `gh api`
- **Tasks** — Wrike folder contents, click to start a session
- **Memory** — search/list/delete entries in the project / session / global
  namespaces
- **Agents** — view/edit the six bundled subagents per project

## GitHub authentication

This app does **not** store a GitHub token. All GitHub operations shell out
to `gh`. To sign in:

```sh
gh auth login
```

Make sure your token has `repo` scope for private repos.

## Wrike authentication

Generate a Wrike Personal Access Token (Settings → Apps & Integrations →
API), then paste it in the app's Settings → Wrike pane. The token lives in
your Keychain under service `com.claudeswarm.tokens`, account `wrike`.

## Notifications

The `notify.sh` hook script is installed once into
`~/Library/Application Support/ClaudeSwarm/bin/` and referenced absolutely
in each project's `.claude/settings.json`. When Claude needs input, the
script POSTs a JSON event to `~/Library/Application Support/ClaudeSwarm/hooks.sock`,
which the app's `HookSocketServer` consumes to:

- Post a `UNUserNotification` (suppressed if the session is foreground)
- Increment the dock badge
- Mark the session with a yellow dot in the sidebar
- Update its DB status to `waitingForInput`

## Memory

Memory is filesystem-backed. Per-project notes live as Markdown with YAML
frontmatter under `<repo>/.claude/memory/`:

- `.claude/memory/global/` — symlink target for cross-project notes
  (actually a shared directory under
  `~/Library/Application Support/ClaudeSwarm/memory/global/`)
- `.claude/memory/project/` — shared across sessions in this project
- `.claude/memory/session/<sessionId>/` — private to one session

Read with `grep -rl` or `Read`; write with `Write`. The bundled `memory`
skill teaches the agent the conventions; it lives at `.claude/skills/memory.md`.

## Smoke test (manual)

Run after build:

- [ ] Add a project, confirm `.claude/agents/*.md`, `.claude/settings.json`,
      `.mcp.json` all exist in the repo
- [ ] Start a session — worktree appears, `claude` launches with `team-lead`
- [ ] Make code changes — Files / Diff / History reflect them
- [ ] Stop typing → yellow dot in sidebar + macOS notification + dock badge
- [ ] Type a reply → indicator clears
- [ ] PR tab → push & create → PR appears on GitHub with seeded title/body
- [ ] PR tab refreshes → CI checks and review comments visible inline
- [ ] Memory tab shows entries written by team-lead / engineer

## Running unit tests

From a terminal:

```sh
swift test --package-path Packages/KeychainKit
swift test --package-path Packages/GitKit
swift test --package-path Packages/MemoryService
swift test --package-path Packages/WrikeKit
swift test --package-path Packages/GitHubKit
swift test --package-path Packages/SessionCore
swift test --package-path Packages/AgentBootstrap
```

(Some tests need `git` on PATH and write to `/tmp` — both fine on a Mac.)

## Things to verify on Mac (I couldn't from a Linux dev box)

1. **`claude` initial-prompt seeding** — confirm `view.send(txt:)` after a
   600 ms warmup is the right way to seed a prompt without breaking
   interactivity. Alternative: write the prompt to a temp file and pass
   `--prompt-file` if Claude Code supports it.
2. **SwiftTerm color palette** — current build uses default xterm colors.
   Tune to match macOS dark/light Terminal palette before shipping.
3. **`.mcp.json` shape** — verify Claude Code accepts the empty
   `{"mcpServers": {}}` form when placed in the worktree root, and that
   user-defined entries merged on top survive bootstrap re-runs.
4. **Hook environment passthrough** — confirm Claude Code preserves
   `CLAUDE_SWARM_SESSION_ID` and `CLAUDE_SWARM_HOOK_SOCKET` env vars to the
   hook subprocess (the hook script reads them).
