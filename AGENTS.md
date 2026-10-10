# AGENTS.md

This file is the canonical guide for AI coding agents in **ai-dev-harness**: a workspace for
AI-driven development of Spring Boot services. It states the rules first, then maps the
repository.

## What this repository is

The harness is the **workspace** that sits beside the code. It holds one folder per service under
`projects/<name>/` and the parts that every service shares: the kit (scripts, workflow, acceptance
test conventions), the coding standards, the standards gate and the skill chain. The code of each
service lives in its own repository, outside this one.

## Invariants

1. **No AI-tool files in a service repository.** `AGENTS.md`, `CLAUDE.md`,
   `copilot-instructions.md`, acceptance suites and helper scripts stay in this workspace
   (`kit/WORKFLOW.md` invariant 2).
2. **The standards gate.** Before the first edit to a service's source file, read
   `standards/GUIDELINES.md` (the routing table) and every guideline file it routes the task to
   (`kit/WORKFLOW.md` invariant 1). Under Claude Code, `hooks/standards-gate.sh` enforces this
   rule. Under any other tool, nothing enforces it: you hold yourself to it.
3. **Work starts and ends in the project folder.** Read `projects/<name>/` first, work in the
   service repository, then close every obligation of the `kit/WORKFLOW.md` close-out table in the
   same change.
4. **`CLAUDE.md` is only a pointer.** Every `CLAUDE.md` holds only `@AGENTS.md`, which points at
   the `AGENTS.md` in the same folder.
5. **English only.** Every file in this repository is written in English.
6. **No employer content.** No organization-internal name, host, path, or copied standard text
   enters this repository. Every rule here is written for any Spring Boot service.

## Library documentation

Before you write, explain, or debug code that uses a library, framework, SDK, API, CLI tool, or
cloud service (Spring Boot, Maven, Flyway, hurl), fetch its current documentation with the
`context7` MCP server, also when you think you know the answer: call `resolve-library-id`, then
`query-docs` with the full question. Use context7 before a web search for library docs. Skip it
for business logic, refactoring, and code review.

## Repository map

| Path | What it is |
|---|---|
| `kit/` | The shared kit: `WORKFLOW.md`, `scripts/` (`run-local`, `mvn-test`, `set-version`, `run-suite`, `check`), `checks/` (the Maven module behind `check.sh`: the ArchUnit rules and the tool versions), hurl conventions in `acceptance-tests/`, and a complete example project in `examples/projects/sample-service/` |
| `projects/<name>/` | One folder per service: `AGENTS.md`, `CLAUDE.md`, `service.env`, `CODEBASE.md`, `GLOSSARY.md`, `docs/adr/`, `acceptance-tests/`, `.scratch/`. The `new-project` skill creates it from a cloned repository |
| `standards/` | The coding standards: `GUIDELINES.md` (the routing table), `guidelines/*.md` (the rules), `gate-routes.txt` (the routes that the standards gate enforces, as data), `check-routes.sh` with its test, and `checks/` (the values of the build checks: Checkstyle configuration, layer model, commit-check limits) |
| `docs/agents/` | How the skills use this workspace: the issue tracker, the triage labels, the domain docs |
| `docs/adr/` | The decisions of the harness itself; a service's decisions live in `projects/<name>/docs/adr/` |
| `.scratch/<feature-slug>/` | Specs and tickets for work on the harness; a service's tickets live in `projects/<name>/.scratch/` |
| `.agents/skills/` | The skill catalog (real files): the chain `to-spec` → `to-tickets` → `implement` / `implement-spec` (with `tdd`) → `code-review` → `pr`, plus `pr-review`, `codebase-map`, `codebase-design`, `domain-modeling`, `diagnosing-bugs`, `grilling`, `grill-with-docs`, `handoff`, `writing-for-agents`; the kit skills `new-project`, `run-acceptance-tests`, `set-version` |
| `.claude/skills/` | One symlink per skill, `<name>` → `../../.agents/skills/<name>` (ADR-0004); a new skill needs its link |
| `hooks/` | The standards gate: `standards-gate.sh` (`pre` blocks an edit in a registered source repository until the routed guidelines are read; `post` records the reads) and its test `test-standards-gate.sh` |
| `.claude/settings.json` | Wires the gate as Claude Code hooks: `pre` on `Write\|Edit\|MultiEdit\|NotebookEdit`, `post` on `Read\|Bash\|Grep\|Glob` |
| `.mcp.json` | The project MCP servers: `context7`. It reads the key from the `CONTEXT7_API_KEY` environment variable; the key itself never goes into the file |
| `scripts/` | Checks of the harness itself: `check-skills.sh` (the skill catalog) and its test `test-check-skills.sh` |

## Where to look

| Need | Read |
|---|---|
| The workflow, its invariants and the close-out obligations | `kit/WORKFLOW.md` |
| The coding standards: which guideline a task needs, and the rule IDs | `standards/GUIDELINES.md` |
| Adding or changing a guideline or a gate route | `standards/GUIDELINES.md`, section "Changing the standards"; then run `bash standards/test-check-routes.sh` |
| Script usage and the `service.env` keys | `kit/scripts/README.md` |
| Running the build checks (Checkstyle, ArchUnit, commit check) or changing a limit they enforce | `kit/scripts/README.md`, section "`check.sh`"; the values are in `standards/checks/`; run `kit/scripts/test-check.sh` after a change |
| Running and gating hurl suites | `kit/acceptance-tests/README.md` |
| The shape of a project folder | `kit/examples/projects/sample-service/` |
| Refreshing a project's `CODEBASE.md` | `kit/regenerating-codebase.md` |
| Specs and tickets: folders, the `Status:` line, close-out | `docs/agents/issue-tracker.md` |
| The five triage roles and their label strings | `docs/agents/triage-labels.md` |
| Which glossary and ADRs to read before you explore | `docs/agents/domain.md` |
| Why the harness is built this way | `docs/adr/` |
| Adapting a copy of the starter: which files to change, the check after each change, the starter-only rules | `docs/customizing.md` |
| Why an edit is blocked, which paths the gate guards, and its known limits | The header of `hooks/standards-gate.sh`; after a change run `bash hooks/test-standards-gate.sh` |
| Checking the skill catalog after you add or edit a skill (links resolve, no foreign or unknown names) | Run `scripts/check-skills.sh`; its test is `scripts/test-check-skills.sh` |
