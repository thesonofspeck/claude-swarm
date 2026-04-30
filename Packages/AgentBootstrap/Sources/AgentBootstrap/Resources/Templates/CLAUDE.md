# Project guidance for Claude Code

This file is loaded automatically by Claude Code into every session in this
repository. Customize it to capture project conventions, hidden constraints,
and the things you'd otherwise have to repeat to every new session.

## Working agreement

- Default agent in this repo is **team-lead** (see `.claude/agents/team-lead.md`).
  Team-lead orchestrates: ux-designer, systems-architect, engineer, qe, reviewer.
- All agents have access to a shared memory MCP server with these tools:
  `mcp__memory__memory_write`, `memory_search`, `memory_get`, `memory_list`,
  `memory_delete`. Use namespace `project:<id>` for shared notes,
  `session:<id>` for private scratch, `global` for cross-project knowledge.

## Style

- Match existing code style. Don't reformat unrelated code.
- Don't write comments that narrate WHAT the code does — names already do that.
- Keep diffs small and focused on the task.

## Verification

Document the quickest way to verify a change here. Examples:
- `swift test --package-path Packages/<X>`
- `npm test`
- `bundle exec rspec spec/foo_spec.rb`

## Hidden constraints

Use this section to capture things that bit you once and you don't want to
re-explain. Examples:
- "DB migrations must be additive — column adds only, no drops in v1."
- "Don't import `<X>` from this directory — circular dep with `<Y>`."

(Delete this template content and write yours.)
