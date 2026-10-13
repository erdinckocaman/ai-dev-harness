# Agent workflow for a service project

The shared rules of every service project in the workspace. Each project `AGENTS.md` states
the two invariants below in one line and points here; this file holds the full rule. A rule
that exists only behind a pointer is a rule an agent can miss, so the one-line cue stays.

"The project" is the service's folder `projects/<name>/`. "The source repository" is the path
in its `Scope` section, which is also `SOURCE_REPO` in its `service.env`.

## Invariants

1. **The standards gate.** Before the **first edit to any source file**, the agent reads the
   routing table `../standards/GUIDELINES.md` and every guideline file that it routes the task
   to. No exceptions, no "small change" carve-out. Under Claude Code, `../hooks/standards-gate.sh`
   blocks an edit until the guidelines that the edited path routes to are read
   (`../docs/adr/0003-gate-path-certain-rules-only.md`). Reading the routing table alone unlocks
   nothing.

2. **No AI-tool files in the source repository.** `AGENTS.md`, `CLAUDE.md` and
   `copilot-instructions.md` are never committed there — that knowledge lives in the project
   instead. For the same reason the project's `acceptance-tests/` and this kit's scripts live in
   the workspace, and local git hooks in the source repository are never committed.

## Coding workflow (workspace-first)

Coding work is **anchored in the project folder**, even though the code lives in the source
repository. Every coding session is bookended by it:

1. **Start in the project.** Read its `CODEBASE.md`, plus `GLOSSARY.md` and `docs/adr/` as the
   task needs — then go work in the source repository.

2. **Follow the standards** (invariant 1).

3. **End in the project.** Close every obligation the change triggers, in the **same change**:

   | If the change touches | Do this | Detail |
   |---|---|---|
   | Modules, build/run commands, package conventions | Refresh the project's `CODEBASE.md` | `regenerating-codebase.md` |
   | An HTTP endpoint (method, path, params, headers, body, status/response contract) | Update the project's `acceptance-tests/suites/*.hurl` (+ `environments/` if the contract changed) and re-run it with `scripts/run-suite.sh`. If the change adds an entry for a **new** endpoint, or rewrites an entry because the contract changed, set that block's `# @requires <version> skip=<var>` to the version in `pom.xml` you are developing — and add the matching `<var>=false` default to `environments/common.env`. | `acceptance-tests/README.md` §"Gating" |
   | Any source file | Compile the service, then run `scripts/check.sh --project <name>`. Fix every finding until it exits `0`. Then review the **whole of every file you touched** against the guidelines step 2 routed you to. | `scripts/README.md` §"`check.sh`" |

   None of these are enforced at build time: the service's own build and CI do not run
   `check.sh`. A whole-file review matters because a violation that the diff leaves untouched —
   a file that never had a file header, for one — is invisible to a diff-only reading.
