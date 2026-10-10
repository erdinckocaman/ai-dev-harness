# Core principles

Status: draft. Every task starts with this file.

These rules apply to every change in every service. The other guideline files add rules for a
kind of file or a kind of change. Tags: see `../GUIDELINES.md`, "How to read a rule".

## Scope of a change

- **CORE-1** `review` — Solve the stated problem only. Do not add a feature, an option or an
  extension point that the task does not ask for.
- **CORE-2** `review` — Choose the simplest design that passes the tests. Add an abstraction
  (interface, base class, strategy) when the second real use appears, not before.
- **CORE-3** `review` — Change only the lines that the task needs. Do not reformat, rename or
  reorder code that the change does not otherwise touch.
- **CORE-4** `review` — Remove what your change makes unused: code, imports, configuration,
  files. Report dead code that existed before; do not delete it in the same change.
- **CORE-5** `review` — Use what Spring Boot, the JDK or an existing dependency already gives
  before you write your own code or add a dependency.

## Proof

- **CORE-6** `review` — Every change of behavior has a test that fails without the change.
- **CORE-7** `review` — Run the tests and `check.sh` before you say the change works. Report a
  step you could not run, and why.
- **CORE-8** `review` — State each assumption in the PR description. When an assumption changes
  the design, ask before you build on it.

## Safety

- **CORE-9** `review` — Commit no secret: no password, key, token or real personal data, also
  not in a test, a fixture or a sample configuration.
- **CORE-10** `review` — Keep each change backward compatible with the running version, or say
  in the PR description why it cannot be and how the rollout handles it.

## Commits

A pull request is merged as one squash commit. Its header is the PR title. A merge commit
(more than one parent), a header that git writes for a revert (`Revert "…"`), and a header that
starts with `fixup!`, `squash!` or `WIP` are exempt from CORE-11 to CORE-13. The squash merge
removes them.

- **CORE-11** `commit-check` — The header has the form `<type>: <subject>` or
  `<type>(<scope>): <subject>`. `<type>` is one of `feat`, `fix`, `refactor`, `perf`, `test`,
  `docs`, `build`, `ci`, `chore`, `revert`. `<scope>` matches `[a-z0-9-]+`. A `!` before the
  colon marks a breaking change.
- **CORE-12** `commit-check` — The header has 72 characters or fewer. The subject starts with a
  lowercase letter and does not end with a period.
- **CORE-13** `commit-check` — The second line is blank. Each body line has 72 characters or
  fewer, except a line that holds a URL.
- **CORE-14** `commit-check` — No file that the branch changes contains a conflict marker: a
  line that starts with `<<<<<<< `, `>>>>>>> `, or is exactly `=======`.
- **CORE-16** `review` — Write the subject in the imperative mood: "add order export", not
  "added order export". The body says why, not what.
- **CORE-17** `review` — One logical change per pull request. The PR title is the header of the
  squash commit: it follows CORE-11, CORE-12 and CORE-16.
