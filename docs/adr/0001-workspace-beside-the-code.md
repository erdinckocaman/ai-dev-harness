# The workspace sits beside the code

> **Status: Accepted.** (2026-10-08)

The harness is a git repository of its own, the **workspace**. It holds the agent instructions,
the knowledge, the acceptance tests and the tickets of each service in `projects/<name>/`. The
code of each service stays in its own repository, the **source repository**, which the project's
`service.env` names as `SOURCE_REPO`. No AI-tool file (`AGENTS.md`, `CLAUDE.md`,
`copilot-instructions.md`), acceptance suite or helper script is committed to a source
repository.

An agent session starts at the workspace root. The agent reads the project folder, does the work
in the source repository, then closes the workflow obligations back in the project folder
(`kit/WORKFLOW.md`).

## Considered Options

- **Commit the agent files into each service repository.** Rejected: the whole team then has to
  adopt, review and maintain files that only one developer uses. One developer cannot work
  agent-first alone.
- **Keep the agent files untracked in the service repository** (a local `.git/info/exclude`).
  Rejected: the files have no history and no backup, and a clean clone loses them.
- **One workspace per service.** Rejected: the kit, the standards, the gate and the skills would
  exist once per service and drift apart.

## Consequences

- A service repository stays exactly as the team keeps it. The team does not see the harness.
- An agent works in two repositories in one change: code in the source repository, knowledge
  and tests in the project folder. The close-out table of `kit/WORKFLOW.md` names what goes
  where.
- An agent session that starts inside a source repository does not load the workspace rules or
  hooks. Only the `AGENTS.md` invariant protects that case.
