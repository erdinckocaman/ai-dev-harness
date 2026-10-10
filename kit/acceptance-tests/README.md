# hurl acceptance suites — running and gating

How every service project runs, gates and writes its [hurl](https://hurl.dev/)
acceptance suite. A project's own `acceptance-tests/README.md` lists its suites and its gated
blocks; this file holds what is the same for all of them. The house style of an entry is
`assertion-conventions.md`.

A suite lives in the workspace **on purpose**, so the source repository stays untouched
(`../WORKFLOW.md` invariant 2). It runs against a running instance of the service: local, dev
or test.

## A project's suite

```
projects/<name>/acceptance-tests/
  suites/         # *.hurl — one dependent chain of entries per file
  environments/   # common.env (constants + gate defaults) + local.env / dev.env / test.env
  reports/        # hurl output (git-ignored)
  README.md       # its suites, its currently gated blocks, its status
```

`baseUrl` is the only per-target variable; every request path keeps its literal `/api/v1/...`
prefix. Constants that are the same on every target live in `common.env`.

## Requirements

- **hurl** — `brew install hurl` (developed against **8.0.1**). One binary, no `package.json`,
  no build system.

## Running

Through the gated runner (see "Gating"), from the kit folder:

```bash
scripts/run-suite.sh --project <name> --env local --app-version <pom version>
```

`--env <name>` picks `environments/<name>.env` (default `local`); `--suite <name>` (repeatable)
picks suites, and without it every suite runs; everything after `--` is forwarded to hurl
verbatim.

Plain hurl works too, from the project's `acceptance-tests/` folder:

```bash
hurl --test --jobs 1 \
  --variables-file environments/common.env \
  --variables-file environments/local.env \
  suites/<suite>.hurl
```

It takes the `common.env` gate defaults, which run every version-gated block.

### Why these flags

- **Two `--variables-file`s.** hurl has no collection-variable scope, so the constants that
  are identical on every target live in `common.env` and only `baseUrl` differs per target.
- **`--test`** turns on test mode: assert-focused output plus a run recap, and it suppresses
  the last response body.
- **`--jobs 1`.** `--test` runs *files* in parallel by default. Sequential keeps the output
  readable and avoids two writers on the shared `dev` database. Entries *inside* a file are
  always sequential — that ordering is the seeding mechanism.
- **No `--continue-on-error`.** Each file is a dependent chain: if the create fails, every
  later entry asserts against an unseeded state, so the first failure is the only informative
  one. Add the flag ad hoc when you want to see how far a broken run gets.
- **Selecting requests.** hurl has no folder concept — you select by *file*, and within a file
  by `--from-entry N` / `--to-entry N` (entry numbers match the numbered comments in the
  `.hurl` files).
- **Debugging a failure.** `--error-format long` prints the failing entry with actual vs.
  expected; `--verbose` adds the equivalent `curl` command and the response headers.

### Reports

- The **`--test` recap** on stdout is the default and the only always-on output.
- A shareable **HTML report** is opt-in: forward `-- --report-html reports/html` and open
  `reports/html/index.html`. `--report-junit reports/junit.xml` and
  `--report-tap reports/report.tap` are also available if a machine-readable form is wanted.

## Gating

Not every entry can run against every target, and one that cannot fails for a reason that has
nothing to do with the service being broken. `run-suite.sh` gates those entries. There are **two
kinds of gate**, because there are two different reasons an entry cannot run:

| Kind | Annotation | Unsatisfiable because | Satisfied by |
|---|---|---|---|
| **Version** | `# @requires 1.3.1 skip=<var>` | the target has not shipped the endpoint yet | `--app-version` ≥ the required version |
| **Precondition** | `# @requires-env <name> skip=<var>` | the target is not *arranged* the way the entry needs | `--precondition <name>` |

Keeping them apart is the point: a precondition is not something a newer release brings, so
`--app-version` must never turn one on. Collapsing both onto `@requires` did exactly that in
an earlier version of this kit — a mail-handoff block was un-skipped by any sufficiently new
`--app-version` and then failed on every healthy target, a false negative in every ordinary run.

### The three moving parts

1. **The annotation** — one line at the head of a gated block in a `.hurl` file:

   ```hurl
   # @requires 1.3.1 skip=skipItemArchive
   ```

   `1.3.1` is the **minimum application version the block needs**, not the version the block
   was written in. If a contract change forces an entry to be rewritten, raise this number to
   the version that changed the contract — the value is always `max(added, last updated)`,
   which is why there is one field rather than an "added in" / "updated in" pair.

   A precondition gate names an arrangement instead, in the same position:

   ```hurl
   # @requires-env mail-transport-unavailable skip=skipMailHandoffFailure
   ```

   A block may carry both kinds; it then runs only when **every** gate is satisfied.

2. **The skip option** — every entry in the block carries the variable the annotation names:

   ```hurl
   [Options]
   skip: {{skipItemArchive}}
   ```

   The variable is **per feature block, not per entry**, and it must cover the block's fixtures
   and cleanups too. Entries chain off each other's `[Captures]`, so skipping half a chain
   leaves the rest asserting against an unseeded state.

3. **The default** — `environments/common.env` carries a value for every gate variable. hurl
   fails a whole file if a `skip:` variable is undefined, so this default is what keeps the plain
   `hurl` command above working unchanged. `run-suite.sh` refuses to run if an annotation has
   no matching default. Version gates default to `false` (run it), precondition gates to `true`
   (skip it) — a plain `hurl` invocation has no way to know how the target is arranged, so the
   only safe default is to leave that block out.

### Running against an older target

```bash
scripts/run-suite.sh --project <name> --env test --app-version 1.2.5
```

`run-suite.sh` collects every annotation, resolves each gate, and passes one
`--variable <var>=true|false` per gate variable to hurl — `--variable` overrides
`--variables-file`, so the `common.env` defaults are the floor and the flag is the override. It
reports on stderr how many blocks it skipped and why.

**Omitting `--app-version` skips nothing on the version axis** — the run behaves exactly like a
plain `hurl` invocation, with a warning on stderr. That is deliberate: forgetting the flag makes
gated entries fail loudly rather than pass silently. Precondition gates are the other way round:
they are skipped until declared, because there is no loud failure to hope for — a healthy target
simply returns success where the entry asserts an error.

### Running a precondition-gated block

```bash
scripts/run-suite.sh --project <name> --precondition mail-transport-unavailable --suite email
```

`--precondition` is repeatable, and asserts *"this target really is arranged that way"* — the
script cannot verify it, so a wrong declaration turns into an ordinary test failure. A
`--precondition` that matches no annotation in the selected suites is rejected outright: it would
otherwise leave the block it was meant to enable skipped, and still report green.

Since the forwarded flags come last and hurl's last `--variable` wins, `-- --variable
<var>=false` is the escape hatch for a one-off run that overrides a gate decision.

### The one thing that can lie to you

Nothing verifies that the version you pass is the version the target actually runs. A service
that keeps `management.endpoints.enabled-by-default: false` and opens only `health` and
`metrics` exposes no build version to read. A stale
`--app-version` skips blocks that would have passed and reports green. The defence is the
script's noisy per-run summary; the real fix is enabling `/actuator/info` + build-info in a
service and having the script read the version off the target, which is deliberately deferred.
`--precondition` is unverifiable in the same way, but errs in the safe direction: it is opt-in,
so forgetting it skips a block rather than inventing a pass.

Entries with no annotation are assumed valid on every version. If you point a suite at a version
old enough to break them, they fail loudly, which is the acceptable direction.
