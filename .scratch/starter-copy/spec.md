# Spec: Make the harness a starter that others copy once

Status: closed — 2026-10-10
Permanent home: `README.md` (section "Make your own copy"), `docs/customizing.md`,
`.github/workflows/test.yml`. Both release blockers below are done.
Source: conversation of 2026-10-10. The owner decided that each company or person copies the
harness once, as a starter, and customizes the copy. The starter sends no updates to a copy
(ADR-0006).

## Problem Statement

The harness works for its owner, but nobody else can start from it. The repository has no remote
and no license. The README shows the folder layout but no prerequisites and no first steps. No
document tells a new owner which files to change for their own company, and which rules bind the
starter only. The README names Codex and opencode, but only Claude Code runs the standards gate.

## Solution

Publish the harness as a template repository. A new owner makes a copy with "Use this template",
follows a first-run section in the README, then follows a customization guide that names every
customization point. CI runs the five test scripts on the starter.

## User Stories

1. As a new owner, I want to make a private copy with a fresh history, so that my services and
   my standards stay inside my company.
2. As a new owner, I want one list of the tools to install and the first steps, so that my first
   session works.
3. As a new owner, I want one list of the files I can change and what each one controls, so that
   I adapt the standards, the routes and the checks to my company.
4. As a new owner, I want to know which starter rules I can drop, so that I keep only the rules
   that bind my copy.
5. As a user of Codex or opencode, I want to know that the gate does not run for my tool, so that
   I do not rely on it.
6. As the starter owner, I want CI to run the test scripts, so that a change to the starter does
   not break a new copy.

## Out of Scope

- Any update or sync from the starter to an existing copy (ADR-0006).
- Running the standards gate under Codex or opencode. This spec only states the limit.

## Release blockers outside this spec

These tickets of the bootstrap effort must be done before the starter is published:

- Bootstrap ticket 03: the owner approves the generic standards.
- Bootstrap ticket 08: the pilot service goes through the whole chain.

The bootstrap tickets live in the owner's knowledge base, not in this repository.

## Testing Decisions

- The five test scripts pass on a clean clone: `hooks/test-standards-gate.sh`,
  `scripts/test-check-skills.sh`, `standards/test-check-routes.sh`,
  `.agents/skills/new-project/scripts/test-new-project.sh`, `kit/scripts/test-check.sh`.
- The leak check of invariant 6 returns no match on the files and on the whole history.
