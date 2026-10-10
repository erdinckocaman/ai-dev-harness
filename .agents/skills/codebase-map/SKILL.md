---
name: codebase-map
description: >-
  Creates or refreshes projects/<name>/CODEBASE.md, the structural and operational map of a
  service whose code lives in its own source repository, so the map stays in the workspace and
  no AI-tool file is committed to the service repository. Use when the user says "set up
  CODEBASE.md", "create/generate the codebase map", "refresh CODEBASE.md", or "init codebase
  knowledge for <project>". It is not for writing or running the service's own code.
---

# codebase-map

This skill writes the workspace-resident equivalent of an "init" file for a coding assistant: a
**`CODEBASE.md` codebase map** in `projects/<name>/`. The map lives in the workspace, **not** in
the service's source repository, so no AI-tool file (`AGENTS.md`, `CLAUDE.md`,
`copilot-instructions.md`) is ever committed there (`kit/WORKFLOW.md` invariant 2). `CODEBASE.md`
is a structural and operational map only. Domain language stays in the project's `GLOSSARY.md`,
decisions in its `docs/adr/`, and coding rules in `standards/GUIDELINES.md`.

The skill has two modes, detected from the files:

- **Create mode**: `projects/<name>/CODEBASE.md` does not exist. Write it, and wire it into
  `projects/<name>/AGENTS.md`.
- **Refresh mode**: `projects/<name>/CODEBASE.md` exists. Re-analyze the source repository and
  rewrite the map. Leave `AGENTS.md` unchanged.

## Steps

1. **Resolve the project.** The only input is the project name, the `projects/<name>/` folder
   name, used exactly as given. Read `projects/<name>/AGENTS.md` and `projects/<name>/service.env`.
   The source repository is `SOURCE_REPO` in `service.env`, which is also the
   `Source repository:` line of the `Scope` section in `AGENTS.md`. Stop and tell the user when:
   - `projects/<name>/` does not exist: the service is not in the workspace yet; suggest the
     `new-project` skill.
   - Neither file names a source repository.
   - The path does not exist on disk: ask the user for the correct path.

   Completion criterion: the source repository path exists and is a git repository.

2. **Detect the mode.** If `projects/<name>/CODEBASE.md` exists, use refresh mode. Otherwise use
   create mode.

3. **Analyze the source repository and write `projects/<name>/CODEBASE.md`.** Follow
   `kit/regenerating-codebase.md`: its steps say what to inspect, and its section layout, length
   bound and caching rules apply in both modes. Read the real files; never guess the stack.
   When the project's `AGENTS.md` names a different regenerate procedure, follow that one
   instead.

   Completion criterion: every section of the layout is filled from files you read, and every
   link in the map points at a file that exists.

4. **Create mode only: wire the map into `projects/<name>/AGENTS.md`.** When its `Where to look`
   table has no row for `CODEBASE.md`, add this row:

   ```markdown
   | Module layout, build/test/run commands | `CODEBASE.md` (regenerate with `../../kit/regenerating-codebase.md`) |
   ```

   When the file has no `Where to look` table, add the table with this row. Change nothing else
   in `AGENTS.md`.

5. **Do not commit.** Print what you created or changed, as paths such as
   `projects/<name>/CODEBASE.md`, and leave the commit to the user.

## Why this shape

AI coding help is reliable for a service only when the agent has an accurate map, and the team
should not have to adopt assistant files in its repository. The map therefore lives in the
workspace, the workflow is **workspace-first** (start by reading the project folder, end by
refreshing the map when the structure changed), and the map is regenerated semantically, not by
a script that breaks as the service changes.
