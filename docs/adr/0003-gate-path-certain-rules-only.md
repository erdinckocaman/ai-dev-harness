# The standards gate keeps to path-certain rules

> **Status: Accepted.** (2026-10-08)

The standards gate (`hooks/standards-gate.sh`) blocks an edit under a registered source
repository until the session has read the guideline files that the edit routes to. A source
repository is registered when `SOURCE_REPO` of a `projects/*/service.env` names it. The routes
are data: the route file `standards/gate-routes.txt` maps a path pattern to the guideline files
it requires, with a one-line reason. The gate has no route list of its own.

The gate enforces only rules that it can decide from the target path: the file extension, the
test source root, a test class name suffix, the migration folder. The routing table in
`standards/GUIDELINES.md` also routes on the kind of change (for example, "changes a REST
contract"). Those routes stay advisory. The agent follows them because invariant 2 of
`AGENTS.md` tells it to, not because the gate blocks it.

A rule that guesses from a file name or from a shell command blocks correct work. A gate that
blocks correct work gets bypassed. So the gate declares its gaps instead of closing them with
guesses.

## Considered Options

- **Route on a class name** (for example, `*Controller.java` requires the REST guideline).
  Rejected: a class name does not prove that the edit touches a REST contract, so the rule
  blocks correct work.
- **Intercept Bash with a "the command mentions a source repository" check.** Rejected: it
  blocks every `cat`, `git diff` and `mvn` run over the source repository. No path-certain rule
  can tell from a command string whether the command writes under the path.
- **An escape hatch** (an environment variable or a warn-only mode). Rejected: the only way past
  the gate is to read the files it names.

## Consequences

- A `sed -i`, a `>` redirect or a heredoc into a source repository passes the gate. The gate
  script lists this gap with its other known limits.
- When a row of the routing table changes what a file kind requires, change the route file in
  the same commit only if the new rule is path-certain.
- A new guideline needs no change to the gate script. It needs a row in the route file, if its
  rule is path-certain.
