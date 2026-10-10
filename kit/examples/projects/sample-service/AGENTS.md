# orders-service — AGENTS.md

The workspace project of the `orders-service` microservice. The code is not here.

## Scope

Source repository: `~/src/orders-service` (mainline `develop`). It is also `SOURCE_REPO` in
`service.env`.

## Invariants

The full rules are in `../../kit/WORKFLOW.md`.

1. **Standards gate:** read the standards guide and the files it routes to before the first
   source-file edit.
2. **No AI-tool files in the source repository:** `AGENTS.md`, `CLAUDE.md`, acceptance suites
   and scripts stay in this project.

## Where to look

| Need | Read |
|---|---|
| Module layout, build/test/run commands | `CODEBASE.md` (regenerate with `../../kit/regenerating-codebase.md`) |
| Run, test, version, acceptance suites | `../../kit/scripts/README.md` |
| This service's acceptance suites and their gated blocks | `acceptance-tests/README.md` |
| The domain terms of this service | `GLOSSARY.md` |
| Decisions about this service | `docs/adr/` |
| Specs and tickets of this service's work | `.scratch/<feature-slug>/` (`../../docs/agents/issue-tracker.md`) |

## Known limits

None yet. Record here where this service does not fit the kit's assumptions.
