# The skill catalog is mirrored by symlink

> **Status: Accepted.** (2026-10-08)

More than one agent tool must see the skills of this workspace. Claude Code reads
`.claude/skills/`. Other agent tools discover skills at `.agents/skills/`. The skill format is
the same for all of them: a `SKILL.md` with `name` and `description` frontmatter.

## One catalog, two views

Every skill is a real directory under `.agents/skills/`. `.claude/skills/` holds one symlink per
skill, which points at the real directory:

```
.agents/skills/tdd/          real directory
.claude/skills/tdd        →  ../../.agents/skills/tdd
```

Both folders list the same names. Edit a skill through either path: it is the same file. There
is no second copy and nothing to keep in sync.

The real files live under `.agents/skills/` because that is the path that is not tied to one
tool. If a project adds a skill of its own, it mirrors the same way, inside the project folder:
`projects/<name>/.claude/skills/<skill>` → `../../.agents/skills/<skill>`.

## Considered Options

- **Copy each skill into both folders.** Rejected: two copies drift silently.
- **Real files under `.claude/skills/`, symlinks under `.agents/skills/`.** Rejected: it ties the
  catalog to one tool. The workspace is meant for any agent tool.
- **One folder only.** Rejected: each tool reads only its own path, so one tool would not see
  the skills.

## Consequences

- A new skill needs its symlink. Create `.agents/skills/<name>/`, then run
  `ln -s ../../.agents/skills/<name> .claude/skills/<name>`. Without the link, Claude Code does
  not see the skill.
- A skill that calls its own script uses a path that works through either view. A path relative
  to the repository root (`.agents/skills/<name>/scripts/...`) works when the agent's working
  directory is the repository root.
- Git on Windows does not create symlinks by default. It writes each link as a text file, and the
  Claude Code view breaks. The kit is macOS-only today (`kit/README.md`), so this limit is
  declared, not fixed.
