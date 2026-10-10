# Coding standards — routing table

Status: approved by the starter owner on 2026-10-10. In a copy, the copy's owner reviews the
rules and sets this line (`docs/customizing.md`, "Approve your standards").

This file is the entry point of the coding standards for every service in this workspace. It
does not hold rules. It tells you which guideline files a task needs, so that you read only what
the task triggers.

- **Paths.** A guideline path in the tables starts at `standards/`: `guidelines/rest-api.md`
  is the file `standards/guidelines/rest-api.md`.
- **Read in place.** Do not copy a guideline into a service repository (`kit/WORKFLOW.md`,
  invariant 2).
- **The gate.** `gate-routes.txt` lists the routes that the standards gate enforces from the
  edited path. The table below also routes on the kind of change. The gate cannot see the kind
  of change, so you apply those rows yourself.

## How to read a rule

Each rule has an ID (for example `JAVA-4`) and one check tag:

| Tag | Who checks the rule |
|---|---|
| `checkstyle` | Checkstyle, with the harness configuration (`kit/scripts/check.sh`) |
| `archunit` | ArchUnit, from the harness module, on the compiled classes (`kit/scripts/check.sh`) |
| `commit-check` | The commit check over the commits since the default branch (`kit/scripts/check.sh`) |
| `review` | You, and the reviewer. A tool cannot decide it. |

A tool rule still applies when the tool is not run. Run `check.sh` before you ask for a review,
and fix every finding. Cite rule IDs in review comments.

## Task start check

1. Read `guidelines/core-principles.md`. Every task starts there.
2. Write down the goal of the task and what you do not know yet. Ask when an unknown changes the
   design.
3. Find every row of the table below that the task triggers. Read each file that the row names.
   A row triggers on the file you edit **or** on the kind of change you make.
4. Define how you will prove the change works: a test, a check, or a run.
5. Change only the files and the lines that the task needs.
6. Before you commit, run `check.sh`, then review every file you touched against the
   `review` rules of the guidelines you read.

## When → Read

| When | Read |
|---|---|
| Any task | `guidelines/core-principles.md` |
| Writing or reviewing any Java code | `guidelines/java-coding-conventions.md` |
| Adding a class, a package, a module or a dependency; editing `pom.xml` or `application*.yml` | `guidelines/project-structure.md` |
| Writing, moving or deleting a test | `guidelines/testing-strategy.md`, then `guidelines/unit-testing.md` or `guidelines/integration-testing.md` for the kind of test |
| Adding or changing an HTTP endpoint, a request or response type, or a status code | `guidelines/rest-api.md` — review entry point: its "Review checklist" section |
| Throwing, catching or mapping an exception; adding a log line; calling another service | `guidelines/error-handling-and-logging.md` |
| Creating, parsing, storing or returning a date, a time or a timestamp; calling `now()`; picking a time zone | `guidelines/time-and-time-zones.md` |
| Writing SQL, a Flyway migration, a JPA entity or a repository query | `guidelines/database-and-flyway.md` |

When a row names a file, read the whole file. A guideline that refers to another guideline does
not replace the other file.

## Changing the standards

- A new guideline gets a row in the table above. If its trigger is path-certain (extension,
  source root, test class suffix, migration folder), it also gets a row in `gate-routes.txt`
  (`docs/adr/0003-gate-path-certain-rules-only.md`).
- A rule with a tool tag gets its check in the same change. A rule that has no check yet is
  tagged `review` until it has one. The values of the checks (limits, patterns, the layer
  model) live in `checks/`; run `kit/scripts/test-check.sh` after a change there.
- A service that must deviate from a rule records the deviation as an ADR in
  `projects/<name>/docs/adr/`, with the rule ID.
- Run `bash standards/test-check-routes.sh` after every change in `standards/`. It fails when a
  route row or a table row names a file that does not exist, or when a guideline file has no row.
