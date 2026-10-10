---
name: new-project
description: Create the workspace project folder projects/<name>/ of a Spring Boot Maven service from its cloned source repository, wired to the kit.
disable-model-invocation: true
---

# New service project

This skill creates `projects/<name>/` for one Spring Boot Maven service whose source repository
is cloned on this machine. The folder starts as a copy of the kit's example project,
`kit/examples/projects/sample-service/` (ADR-0002), with `service.env` filled from the
repository, so the kit scripts work for the service at once.

The invocation is `/new-project <repository path> [--name <name>]`. Paths in this file start at
the workspace root. Run the commands from there. The bundled script does the discovery, the fit
check and the files:

```text
.agents/skills/new-project/scripts/new-project.sh
```

You do the parts that need judgment: the name, the scope text, `CODEBASE.md`. These rules hold
for the whole run:

- **Leave every change uncommitted.** The user reviews the new files first.
- **Create only what is absent.** The script never overwrites a file; your own steps keep the
  same rule for every file that existed before the run.
- **Take input from the repository's README, `pom.xml` files and code.** AI-tool files that a
  teammate committed there (`AGENTS.md`, `CLAUDE.md`, `copilot-instructions.md`) stay unread,
  unedited and unreported.

Every run of the script ends on one exit status. Act on it the same way in every step:

| Exit | Meaning | Action |
|---|---|---|
| 0 | Done | Continue. |
| 1 | Stopped before any write | When the message says to choose another project name, go back to step 2. Otherwise give the user the message and end the run. |
| 2 | The call was wrong | Correct the arguments and run again. |
| 3 | A write failed | Give the user the error. After the cause is fixed, a second run creates what is still absent. |

## 1. Dry run

Without a repository argument, ask the user for the path of the cloned repository and wait.
Then run:

```bash
.agents/skills/new-project/scripts/new-project.sh --dry-run [--name <name>] <repository path>
```

A dry run writes nothing. Its report gives the proposed project name, the discovered
`service.env` values (empty when not found), the root version, the findings of the fit check,
and the status of each file.

## 2. Confirm the name and the scope

- **Name**: propose the name that the report gives. A project whose `service.env` already names
  this repository keeps its name.
- **Scope**: needed only when the report lists `AGENTS.md` as `absent`. Draft one to three
  sentences on what the service does, from the repository's `README.md` and the root `pom.xml`
  (`<name>`, `<description>`, `<modules>`).

Ask for both in one message and wait. When the user changes the name, do the dry run again with
`--name <name>`, because the file statuses depend on the name.

This step is complete when the user has confirmed the name and, if needed, the scope text.

## 3. Run the script

```bash
.agents/skills/new-project/scripts/new-project.sh --name <name> <repository path>
```

An `AGENTS.md` that the script creates records the findings in its "Known limits" section. This
step is complete when the script exits 0.

## 4. Add the scope text

When this run created `projects/<name>/AGENTS.md`, add the confirmed scope text under its
`## Scope` heading, before the `Source repository:` line, wrapped at 100 characters. Change
nothing else in the file. An `AGENTS.md` that existed before the run stays as it is.

## 5. Write CODEBASE.md

When the report lists `CODEBASE.md` as `absent`, run the `codebase-map` skill for `<name>`. The
new `AGENTS.md` already has the `CODEBASE.md` row, so `codebase-map` follows
`kit/regenerating-codebase.md` and leaves `AGENTS.md` unchanged. When `CODEBASE.md` exists, leave
it.

This step is complete when `projects/<name>/CODEBASE.md` exists.

## 6. Summarize

Tell the user, with paths:

- every file that the run created, `CODEBASE.md` included;
- every file that it skipped because it existed, and every example file it left out as the
  sample service's own (its suites and remote targets: write the service's own when a change
  touches an endpoint);
- every finding, and, for an `AGENTS.md` that existed before the run, each finding that its
  "Known limits" does not record; the user decides about those;
- that nothing is committed.

The script's own test is `.agents/skills/new-project/scripts/test-new-project.sh`; run it after a
change to the script or to `kit/examples/projects/sample-service/`.
