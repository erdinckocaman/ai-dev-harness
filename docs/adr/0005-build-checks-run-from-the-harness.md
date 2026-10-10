# Build checks run from the harness

> **Status: Accepted.** (2026-10-08)

Mechanical rules are checked by a tool, not by an LLM review: format, line length, the copyright
header, layering, conflict markers. A tool gives the same result every time. An LLM review does
not.

The checks run from the harness against the source repository, with no change to the service's
`pom.xml`. `kit/scripts/check.sh --project <name>` runs:

- Checkstyle, with a configuration file that the harness owns (in `standards/`).
- ArchUnit rules from a module that the harness owns, against the service's compiled classes.
- A commit check over the commits since the default branch: the header, the line length and
  conflict markers.

## Considered Options

- **Add the Checkstyle and ArchUnit plugins to each service's `pom.xml`.** Rejected as the
  default: it changes the team's build, and it conflicts with ADR-0001 (the workspace sits
  beside the code). A team that wants the checks can adopt the same configuration files into its
  own build. The harness does not require it.
- **Leave the mechanical rules to the LLM review.** Rejected: the result differs between runs,
  and a reviewer misses a violation in an unchanged part of a file.

## Consequences

- The team's build stays as the team keeps it.
- The configuration files and the ArchUnit module are versioned once, in the harness. A rule
  change reaches every service at once (ADR-0002).
- The service must compile before the ArchUnit rules can run, because they read the compiled
  classes.
- The checks run only when the agent or the developer runs `check.sh`. The service's own CI does
  not run them. `kit/WORKFLOW.md` names `check.sh` in the close-out table.
