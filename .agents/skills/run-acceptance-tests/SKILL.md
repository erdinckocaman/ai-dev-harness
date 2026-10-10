---
name: run-acceptance-tests
description: >-
  Runs the hurl acceptance suites (acceptance-tests/suites/*.hurl) of a service project, a
  projects/<name>/ folder with a service.env, against a local, dev or test instance of the
  service. Use when the user asks to run or check the acceptance, regression or hurl tests of a
  service ("run the acceptance tests", "run the hurl tests on dev"), or reports a "command not
  found: hurl" or "input file can not be read" error while running them by hand.
---

# Run a service's acceptance tests

A service's suites live in the workspace on purpose, in `projects/<name>/acceptance-tests/`, so
the source repository stays untouched (`kit/WORKFLOW.md` invariant 2). They run through the
kit's gated runner, `kit/scripts/run-suite.sh`, with the `hurl` binary, against a running
instance of the service.

- Running and gating in full: `kit/acceptance-tests/README.md`.
- The project's suites, its gated blocks with their preconditions, and what a healthy run
  reports: the project's own `acceptance-tests/README.md`. Read it when a result surprises you.

Paths in this file start at the workspace root. Run the commands from there.

## 1. Find the project

Take the first rule that applies:

1. **The request names it**: a folder name under `projects/`, or the `SERVICE_NAME` of exactly
   one `projects/*/service.env`.
2. **The working directory is in it**: `pwd -P` is `projects/<name>` of the workspace, or a
   folder below it.
3. **Neither**: ask the user which project, and wait for the answer. A project that only the
   conversation so far suggests is a guess.

Read `projects/<name>/service.env`. If the file does not exist, stop and tell the user that
`projects/<name>/service.env` is missing, so `<name>` is not a service project; the `new-project`
skill creates one. Run nothing.

When `projects/<name>/acceptance-tests/suites/` holds no `.hurl` file, stop and tell the user
that the project has no suites yet. A suite is written when a change touches an HTTP endpoint
(the close-out table of `kit/WORKFLOW.md`).

Pass `--project <name>` to every kit script below, so the target does not depend on the working
directory.

## 2. Make sure the target answers

`hurl` must be installed (`brew install hurl`; the kit is developed against 8.x).

- **Local** (`--env local`, the default): the target is `baseUrl` in the project's
  `acceptance-tests/environments/local.env`. Check that it answers, with
  `<baseUrl>/actuator/health` when the service has Spring Boot Actuator.
  - It answers: run against that instance, and leave it running afterwards. It can be the user's
    IDE run.
  - It does not answer: start the service in the background with
    `kit/scripts/run-local.sh --project <name>` (it builds first), and wait until it answers.
    After the run, stop it with the same command plus `--stop`. If `run-local.sh` stops because
    the port is in use, give the user the PID it names and wait.
- **A remote target** (`--env dev`, `--env test`): the target is `baseUrl` in
  `acceptance-tests/environments/<env>.env`. When that file does not exist, ask the user for the
  base URL and stop. When the host does not resolve or the connection is refused, tell the user:
  the target may need a network or VPN that this machine is not on.

## 3. Run every suite

Pass `--app-version` with the version the target runs:

- **Local**: the root `pom.xml` `<version>` of the source repository.
  `kit/scripts/set-version.sh --project <name>` prints it as `current version: X.Y.Z` and changes
  nothing.
- **A remote target**: the root `pom.xml` `<version>` of the deployed commit. If you cannot read
  it, ask the user.

```bash
kit/scripts/run-suite.sh --project <name> --env local --app-version <version>
```

Without `--suite`, the runner runs every suite. When the user asks for one flow, add only that
`--suite`. Without `--app-version`, the runner skips nothing on the version axis, so a target
older than the suites fails at its first newer entry.

### Variations

- **The target runs an older version**: pass its version, e.g. `--env dev --app-version 1.3.0`.
  The runner reads the `# @requires <version> skip=<var>` annotations, skips the blocks the
  target is too old for, and reports on stderr what it skipped.
- **A block that needs the target arranged a certain way**: it carries
  `# @requires-env <precondition> skip=<var>` and stays skipped until you declare the
  arrangement, e.g. `--precondition store-unavailable --suite items`. The project's README lists
  its preconditions. Declare one only when the target really is arranged that way: on a healthy
  target the block gets a success where it asserts an error. `--app-version` never turns these
  on.
- **Raw hurl** (no runner): the command in `kit/acceptance-tests/README.md` §"Running", run from
  the project's `acceptance-tests/` folder (its paths are relative). It takes the `common.env`
  gate defaults, which run every version-gated block.
- **Part of a file**: forward `-- --from-entry N --to-entry M`. The entry numbers match the
  numbered comments in the `.hurl` files.
- **Shareable HTML report**: forward `-- --report-html reports/html` (the runner resolves it in
  the project's `acceptance-tests/`) and point the user at
  `projects/<name>/acceptance-tests/reports/html/index.html`. `--report-junit` and
  `--report-tap` give machine-readable output.
- **Diagnosing a failure**: run again with `-- --error-format long` (actual vs. expected on the
  failing entry) and, if needed, `--verbose` (the equivalent curl command and the response
  headers).

## 4. Report

Report the project, hurl's run recap (executed files and requests, succeeded vs. failed) and the
runner's skip summary to the user. If an entry failed, show which file and line failed and the
actual-vs-expected values before you propose a fix. Without `--continue-on-error`, the run stops
at the first failure in a file. Later entries in a file depend on earlier ones, so one early
failure can be the only real problem.
