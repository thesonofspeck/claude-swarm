---
name: memory
description: Persist and recall durable notes scoped to project, session, or global so the agent doesn't re-derive things across runs. Read this skill before answering anything where prior context might exist; write to it whenever you make a decision worth remembering.
---

# Memory

Memory entries are plain Markdown files under `.claude/memory/`. There is no
external service — read and write them with `Read`, `Write`, `Edit`, `Glob`,
and `Grep` like any other file.

## Layout

```
.claude/memory/
  global/                       # shared across every project on this machine
    <slug>.md
  project/                      # shared across every session in this project
    <slug>.md
  session/<sessionId>/          # private to one session
    <slug>.md
```

Default to `project/` unless a note is clearly machine-wide (`global/`) or
clearly throwaway / session-private (`session/<sessionId>/`).

## File format

Every entry is YAML frontmatter + a Markdown body. Keep the body short and
self-contained — one decision, one fact, one snippet per file.

```
---
id: 2025-04-30-grdb-fts-choice
key: persistence/grdb-fts-choice
tags: [arch, persistence]
created: 2025-04-30T10:14:00Z
updated: 2025-04-30T10:14:00Z
---

We picked GRDB + FTS5 over CoreData because we need full-text search
on transcripts and the schema is small. Migrations live in
PersistenceKit/Schema.swift.
```

Frontmatter fields:

- `id` — stable, human-readable, unique within the namespace. Format
  `YYYY-MM-DD-<short-slug>` is fine.
- `key` — optional `slash/separated/path` for grouping (e.g.
  `persistence/grdb-fts-choice`). Useful when you'll search by topic.
- `tags` — short flat list. Use lowercase, hyphenated, no spaces.
- `created` / `updated` — ISO 8601 UTC.

The filename is the `id` plus `.md`. Nothing else parses the directory, so
you can pick any slug that won't collide.

## Reading

- **Recent entries in this project**:
  `ls -t .claude/memory/project/*.md | head -20`
- **Search by content**:
  `grep -rl --include='*.md' "GRDB" .claude/memory/`
- **Search a single namespace**:
  `grep -rl --include='*.md' "auth cookie" .claude/memory/project/`
- **Inspect**: `Read` the file like any other.

Always check memory before doing investigative work that may have been
done before — a 2-second `grep` saves a 2-minute re-derivation.

## Writing

When you make a decision worth remembering — an architectural choice,
a non-obvious gotcha, a working command, a credential location, an API
quirk — write a new file:

1. Pick the namespace: `project/` (default), `session/<sessionId>/`, or
   `global/`.
2. Pick an `id` and create `<.claude/memory/<namespace>/<id>.md>`.
3. Fill in frontmatter and a short body.

Update an existing entry by editing it in place and bumping `updated`.

## When to write

Good candidates:

- "We chose X because Y" decisions.
- Reproduction steps for a bug that took effort to find.
- Locations of important things ("the auth cookie is set in `Session.swift:42`").
- Working commands that are easy to forget.
- Wrike custom-status IDs, GitHub workflow names, anything per-workspace.

Bad candidates (don't pollute memory):

- Generic facts already in docs or obvious from the code.
- Verbatim conversation transcripts.
- Anything secret (tokens, passwords) — never write those.

## When to delete

If a note becomes wrong, fix it in place. If a feature is removed and the
note no longer applies, delete the file. Memory is curated, not append-only.
