# The harness is a starter that each owner copies once

> **Status: Accepted.** (2026-10-10)

This repository is a **starter**. A company or a person makes one copy of it, the **copy**, and
then owns every file in that copy. The copy changes the standards, the gate routes, the build-check
values, the skills, the kit and the `AGENTS.md` invariants as its owner needs. The services of the
copy live in its own `projects/<name>/` folders.

The copy is made once. After that, the starter and the copy are independent: the starter does not
send updates to a copy, and it makes no promise that a later merge from the starter works. The
starter keeps `projects/` empty.

## Considered Options

- **One shared workspace that every user clones.** Rejected: each user's service knowledge and
  tickets would land in one shared repository, and each user's changes to the standards would
  conflict with every other user's.
- **A fork that merges starter updates when it wants.** Rejected: the copy changes the same files
  that the starter changes (the standards, the routes, the skills), so a merge conflicts, and a
  merge that works by accident gives a false promise.
- **A supported sync: the starter keeps its core apart from the customization points.** Rejected
  for now: it needs an overlay design for the standards, the routes and the skills before the
  starter has a second user.

## Consequences

- ADR-0002 still holds inside each copy: a copy has one kit and no per-service copies of it. The
  copy in this ADR is one copy of the whole workspace, not a copy of the kit per service.
- A fix in the starter reaches only new copies. An existing copy takes a fix by hand, if it wants
  it.
- Some rules of the starter bind the starter only, not a copy: a copy can drop "English only"
  and "No employer content" (`AGENTS.md` invariants 5 and 6), and its owner approves its own
  standards.
- A GitHub fork of a public repository cannot be private. A company copy is made with "Use this
  template" (or a clone pushed to a new repository), which also starts the copy with a fresh
  history.
