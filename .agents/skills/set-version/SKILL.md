---
name: set-version
description: Set or bump the Maven and Helm application version of a service project.
disable-model-invocation: true
---

# Set a service's version

`kit/scripts/set-version.sh` rewrites the version in every `pom.xml` of the source repository
and the Helm `appVersion`, and then verifies its own result (`kit/scripts/README.md`
§`set-version.sh`). It changes no git state: the commit stays with the user.

The invocation is `/set-version [<project>] [bump [patch|minor|major] | X.Y.Z] [--repo <path>]`.
Paths in this file start at the workspace root. Run the commands from there.

## 1. Find the project

Take the first rule that applies:

1. **An argument names it**: the argument that is not `bump`, a segment name, a version or
   `--repo <path>`. It is a folder name under `projects/`, or the `SERVICE_NAME` of exactly one
   `projects/*/service.env`.
2. **The working directory is in it**: `pwd -P` is `projects/<name>` of the workspace, or a
   folder below it.
3. **Neither**: ask the user which project, and wait for the answer. A project that only the
   conversation so far suggests is a guess.

Read `projects/<name>/service.env`. If the file does not exist, stop and tell the user that
`projects/<name>/service.env` is missing, so the kit has no source repository for `<name>`.
Change nothing.

## 2. Read the version arguments

- No version argument: pass `bump` (a patch bump). Without a version argument the script only
  prints the current version.
- `bump`, `bump patch`, `bump minor`, or `bump major`: pass it as given.
- `X.Y.Z`: pass the exact strict semantic version.
- `--repo <path>`: pass it on. Without it, the script targets `SOURCE_REPO` from `service.env`.

## 3. Run the script

Run `git -C <repo> status --short` on the target repository first, so that you can keep and
report the changes that were there before. Then run:

```bash
kit/scripts/set-version.sh --project <name> [--repo <path>] <version arguments from step 2>
```

Always pass `--project`, so the target does not depend on the working directory. The script's
output is the source of truth for the changed files and the resulting version.

When the script stops because a version is not strict `MAJOR.MINOR.PATCH` (a `-SNAPSHOT` root
version, for one), give the user its message and change nothing by hand: the project's
`AGENTS.md` "Known limits" is where that gap is recorded.

The task is complete when:

- the script exits with status 0, which means every POM and every Helm chart reports the target
  version;
- the final response states the project, the old version, the new version, and the uncommitted
  files.

When the script prints `version already <X.Y.Z> — no change`, say that nothing changed.
