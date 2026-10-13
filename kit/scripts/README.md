# scripts/

Operational helpers for every service project. They live in the workspace, not in the code
repositories, so no tooling file is committed to a source repository
(`../WORKFLOW.md` invariant 2).

## Choosing the project

Every script works on one service project, `projects/<name>/` of the harness, and reads its
`service.env`.

- `--project <name>` names it, from anywhere;
- without the flag, the script uses the project whose folder holds the working directory;
- with neither, it stops with exit `2` and its usage.

`--repo <path>` still overrides the source repository of `service.env`.

## `service.env`

`lib/service-env.sh` is the one parser of `service.env`: the kit scripts, the `new-project`
script and the standards gate (`hooks/standards-gate.sh`) all read the file through it. No
script sources `service.env`. The rules:

- One `KEY=value` per line; blank lines and `#` comment lines are skipped. No quotes.
- Spaces around the key and around the value are dropped.
- A key that appears twice takes the value of its last line.
- A value `~`, or one that starts with `~/`, starts at `$HOME`.
- A relative `SOURCE_REPO` or `FILE_HEADER` is relative to the project folder, the folder that
  holds `service.env`, not to the working directory. A trailing `/` is dropped.
- An unknown key, or a line that is not `KEY=value`, stops a kit script. The gate and
  `new-project` read only the key they need and skip such lines.

The `new-project` skill writes it from the source repository when it creates the project.

| Key | Value | Read by |
|---|---|---|
| `SOURCE_REPO` | Path of the source repository; a relative path is relative to the project folder | `run-local.sh`, `mvn-test.sh`, `set-version.sh`, `check.sh` (`--repo` overrides it) |
| `SERVICE_NAME` | The container module name without `-container`; the root `artifactId` for a single-module service | `run-local.sh` messages |
| `SERVICE_PORT` | `server.port` of the container module | `run-local.sh`: port check and `--stop` |
| `CONTAINER_MODULE` | The `*-container` module directory; `.` for a single-module service | `run-local.sh`: the module it launches |
| `MAIN_CLASS` | Simple name of the `@SpringBootApplication` class | `run-local.sh --stop`: tells the service's JVM from another port holder |
| `HELM_CHART` | The directory under `k8s/helm/` | No script. It records the chart whose `appVersion` `set-version.sh` rewrites |
| `ROOT_ARTIFACT_ID` | `artifactId` of the root `pom.xml` | `set-version.sh`: finds the root version |
| `DEFAULT_BRANCH` | `origin/HEAD` of the source repository | `check.sh`: the commit check runs over `origin/<DEFAULT_BRANCH>..HEAD` |
| `FILE_HEADER` | Optional. A file with the lines that every Java source must start with; a relative path is relative to the project folder | `check.sh`: the file header check. Without the key, the check is off |

## `run-local.sh` — start the service locally with an env file

Loads a `KEY=VALUE` env file (skipping comments and blank lines), pins the JDK
(`MS_KIT_JDK`, default `21`), and launches the service's container module
(`CONTAINER_MODULE`) via `mvn spring-boot:run`. The Spring profiles activated are
`<profile>,local`.

```bash
scripts/run-local.sh --project orders-service
scripts/run-local.sh --project orders-service --env ~/.ms-kit/local.env --profile dev
```

Run it in the background: it builds every module first, then holds the terminal while the
service runs.

| Flag | Default | Description |
|---|---|---|
| `--project <name>` | the project of the working directory | The service project |
| `--env <path>` | `$MS_KIT_ENV_FILE`, else `~/.ms-kit/local.env` | Path to the env file |
| `--profile <name>` | `local` | Spring profile to activate; `local` is always appended after it |
| `--repo <path>` | `SOURCE_REPO` | Source repo path |
| `--stop` | — | Stop a running instance and exit; no repo and no build needed |

The env file is **exported line by line, never sourced**. A `KEY=VALUE` file is not a shell
script: zsh stops at the first key that is not a valid identifier (`SOME_KEY-PREFIX=…`), and
bash cuts a value at an unquoted `;` (a connection string loses its second half). Invalid keys
are skipped with a warning.

### Failure guards

Two failure modes are checked explicitly, because neither surfaces on its own:

- **Port already in use.** Before building, the script fails if the HTTP port is already
  bound, naming the offending PID. Without this a second instance runs a full reactor build
  only to die on `Port … was already in use`. The port checked is `$SERVER_PORT` if the env
  file sets it (Spring relaxed binding maps it onto `server.port`), otherwise `SERVICE_PORT`.
- **Failed startup reported as success.** `spring-boot-devtools` runs the application on the
  `restartedMain` thread, so Maven's main thread returns normally and prints `BUILD SUCCESS`
  **even when the Spring context fails to refresh** — a failed startup would otherwise exit
  `0`. The script scans the run output for Spring's failure markers and exits `1`, reporting the
  root cause. Without devtools the guard is harmless.

### Stopping

```bash
scripts/run-local.sh --project orders-service --stop
```

A launch is a **three-process chain** — the script, the Maven process, and the forked
application JVM that actually holds the port. `Ctrl-C` in the launching terminal tears the
whole chain down, but a background or orphaned launch does not: killing only the JVM leaves
Maven behind, and killing only Maven orphans the JVM. `--stop` locates the process listening
on the port, walks *up* to its Maven and script ancestors, and terminates all of them,
`SIGTERM` first and `SIGKILL` only if the port is still bound after 20s.

It refuses to kill a process that holds the port but is not the service — its command line
names neither `MAIN_CLASS` nor the source repository — so an unrelated listener is reported
rather than killed. Exit status is `0` when the port ends up free (including when nothing was
running), `1` otherwise.

---

## `mvn-test.sh` — run selected test classes with a clear result

Runs the given test classes of one module on the pinned JDK, then reads the surefire XML
reports that this run wrote and prints one line per top-level class (tests, failures, errors,
skipped), the failing test names, and a total.

```bash
scripts/mvn-test.sh --project orders-service orders-domain OrderTest
scripts/mvn-test.sh --project orders-service orders-domain 'OrderTest#cancel_twice_isIdempotent' MoneyTest
scripts/mvn-test.sh --project orders-service --am orders-application OrderApplicationServiceTest
```

`<module>` is a module directory name, a path from the repo root, or `:artifactId`. `--am` also
builds the modules it depends on, so it does not compile against stale sibling jars. Exit
status: `0` passed, `1` test or build failure, `2` usage error, `3` the build passed but no test
ran. The full Maven log path is printed first.

### Why plain surefire output misleads

Verified on surefire 3.5.5 with the JUnit Platform provider:

- **`Tests run: 0` on `@Nested`-only classes.** Surefire prints a `Tests run: 0 … in <Class>`
  line for the outer class, and labels the real counts with the nested classes' `@DisplayName`.
  The XML `<testsuite tests="…">` total is correct; the script reads only that.
- **A method filter drops nested classes.** A bare `-Dtest=Foo` runs Foo's `@Nested` classes, but
  only while no filter entry names a method. Once one does, `Foo` and `Foo#m` both miss them. The
  script pairs each entry with `Foo$*` (or `Foo$*#m`). It does not use `Foo*`, because that also
  matches other classes, such as `FooBarTest`.
- **`mvn -q` prints nothing on success,** and an unknown class name passes silently with
  `-Dsurefire.failIfNoSpecifiedTests=false`. The script exits `3` when the total is 0.

Skipped tests are reported, not passed: Testcontainers tests skip without Docker.

---

## `set-version.sh` — bump / set the Maven version

A multi-module Maven reactor duplicates its version in **every** `pom.xml`: the root
`<version>` plus each child module's `<parent><version>`, and once more as `appVersion` in the
Helm chart (`k8s/helm/<chart>/Chart.yaml`). Editing them by hand is error-prone: a CI that reads
`project.version` to name the built jar breaks on a single stale pom, and a stale `appVersion`
mislabels the deployed release.

`set-version.sh` rewrites all of them consistently in one command. The root version is the
first `<version>` after the root pom's `<artifactId>` named by `ROOT_ARTIFACT_ID`
(`lib/pom.sh`; the fit check of `new-project` reads it the same way).

```bash
scripts/set-version.sh --project orders-service                 # print the current version + usage
scripts/set-version.sh --project orders-service 1.3.0           # set an exact version
scripts/set-version.sh --project orders-service bump            # patch bump: 1.2.5 -> 1.2.6
scripts/set-version.sh --project orders-service bump minor      # 1.2.5 -> 1.3.0
scripts/set-version.sh --project orders-service bump major      # 1.2.5 -> 2.0.0
```

- **Strict `MAJOR.MINOR.PATCH`.** Both the current version and any explicit target must be
  plain numeric `X.Y.Z`; qualifiers/SNAPSHOT are rejected, which keeps bump arithmetic
  unambiguous.
- **Edits poms and `Chart.yaml` only.** No git, no maven, no commit/tag/build — committing
  the change is yours to do.
- **`appVersion` is forced, not substituted.** Every `Chart.yaml`'s `appVersion` is set to
  the target regardless of what it held before, so a chart that drifted out of sync with the
  poms is corrected even when the pom version is already the target. The chart's own
  `version:` field is the *chart revision*, a separate number, and is never touched.
- **Self-verifying.** After editing it fails loudly if any stale version reference remains,
  the root pom doesn't report the target, or a chart's `appVersion` isn't the target. A true
  no-op (everything already at the target) exits cleanly.
- **Module-list agnostic.** Poms and charts are discovered with `find` (excluding
  `target/`), so adding or removing a module needs no change here.

---

## `check.sh` — run the mechanical checks of the standards

Runs the checks of every rule with a tool tag (`../../standards/GUIDELINES.md`, "How to read a
rule") against the source repository, from the workspace. The service's `pom.xml` does not
change (`../../docs/adr/0005-build-checks-run-from-the-harness.md`).

```bash
scripts/check.sh --project orders-service
```

Compile the service first (`mvn compile`): the ArchUnit rules read the compiled classes. Every
finding is one line that starts with the rule ID, so you can look the rule up in the guideline:

```
JAVA-1  src/main/java/com/example/orders/service/OrderService.java:14: Line is longer than 120 characters (found 144).
STRUCT-2  layer domain may not use layer service (may use: domain): Method <...OrderNames.nameOf(...)> calls method <...OrderService.find(...)> in (OrderNames.java:8)
CORE-11  fdd107f "Added a property file": not <type>(<scope>): <subject>, type one of feat|fix|...
```

| Check | What it reads | Rules | Values in |
|---|---|---|---|
| Checkstyle | `src/main/java` and `src/test/java` of every module (`target/` is skipped) | `checkstyle` tag: JAVA-1 to JAVA-13, ERR-3, TEST-8 to TEST-10 (test sources only) | `standards/checks/checkstyle.xml` |
| ArchUnit | `target/classes` of every module that has `src/main/java` | `archunit` tag: STRUCT-1 to STRUCT-4, JAVA-16, JAVA-21, REST-4, REST-10, ERR-1, ERR-7, ERR-14, TIME-1, TIME-4, TIME-6, DB-21 | `standards/checks/architecture.properties` (layers, allowed uses, annotation placement, the layers that STRUCT-3, ERR-7 and DB-21 name) |
| Commit check | The commits `origin/<DEFAULT_BRANCH>..HEAD`; the files that differ from the merge base in the working tree, untracked files included | `commit-check` tag: CORE-11 to CORE-14, DB-11, DB-12 | `standards/checks/commit-check.conf` |
| File header | Every Java source; only when `service.env` sets `FILE_HEADER` | — (opt-in per project) | The `FILE_HEADER` file |

| Flag | Default | Description |
|---|---|---|
| `--project <name>` | the project of the working directory | The service project |
| `--repo <path>` | `SOURCE_REPO` | Source repo path |

Exit status: `0` no violation, `1` a violation, `2` usage error, `3` a check could not run. The
script runs every check, then reports. A check that cannot run is reported by name with the
reason, and never counts as passed: no `java`, java older than 21, no `mvn` when `kit/checks/`
needs a build, no `target/classes`, a main source newer than its class file (stale classes), no
`origin/<DEFAULT_BRANCH>` (run `git fetch origin`), or no `@SpringBootApplication` class (the
base package of the layers is its package).

- **The values live in `standards/checks/`.** A limit, a pattern or a layer is in one file;
  change it there, not in the script. A rule change also changes the guideline text in
  `standards/guidelines/` (`../../standards/GUIDELINES.md`, "Changing the standards").
- **The tool versions live in `kit/checks/pom.xml`.** `kit/checks/` is a Maven module of the
  workspace: the ArchUnit rules (`dev.aidevharness.checks`) and the classpath of both tools.
  The first run, and the first run after a change in the module, builds it with Maven (the
  dependencies are downloaded once); the build goes to `kit/checks/target/`, which git ignores.
- **Why the Checkstyle CLI, and not the Maven plugin.** `mvn checkstyle:check` on the service
  would run inside the service's build: it merges with a plugin configuration that the service
  may already have, and it uses the plugin's default Checkstyle version, which is too old for
  current Java syntax. The CLI on the module's classpath runs a pinned Checkstyle, on exactly
  the source folders it is given, without the service's build.
- **The working tree counts.** The conflict-marker and migration checks read the files as they
  are now, so you can run `check.sh` before you commit. The message checks read the commits.
- **Exempt commits.** A merge commit (two parents), a header that starts with `Revert "`, and a
  header that starts with `fixup!`, `squash!` or `WIP` (`FIXUP_HEADER`) are exempt from CORE-11
  to CORE-13. The squash merge removes them.
- **The file header is opt-in.** The standards have no header rule, because a header
  text belongs to an organization. Put the header lines in a file (for example
  `projects/<name>/file-header.txt`) and set `FILE_HEADER=file-header.txt`. The check compares
  the first lines of each Java source with the file, character for character.
- **The test.** `scripts/test-check.sh` builds a small Spring-Boot-shaped repository in a temp
  folder (compiled with `javac` against annotation stubs), seeds one violation per case, and
  asserts the exit status and the rule ID. It takes about 20 seconds after the first build of
  `kit/checks/`.

---

## `run-suite.sh` — run the hurl acceptance suites, gated

Runs the project's `acceptance-tests/suites/*.hurl` against a running instance, after it has
resolved every gate annotation. Without `--suite` it runs every suite of the project.

```bash
scripts/run-suite.sh --project orders-service --env local --app-version <pom version>
```

The flags, the gates and the house style: `../acceptance-tests/README.md`.
