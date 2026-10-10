# One kit, not a copied template

> **Status: Accepted.** (2026-10-08)

The scripts, the workflow and the acceptance-test conventions exist once, in `kit/`. A service
does not get a copy. It gets a project folder with a small `service.env`: the source repository
path, the port, the container module, the main class and similar values. Every kit script takes
`--project <name>`, or finds the project from the current folder, and reads its values from that
`service.env`.

The kit started as the standalone `ms-kit` repository. Its history is merged into `kit/`, and
the default `MS_KIT_PROJECTS_DIR` is `projects/` beside the kit folder, so the scripts find the
projects with no change.

## Considered Options

- **A template repository that each service copies.** Rejected: each copy drifts. A fix to a
  script must then be applied once per service, and in practice it reaches only some of them.
- **A per-service fork of a script when the service differs.** Rejected: the fork is a copy with
  the same drift. A service that does not fit the kit records the gap in its own `AGENTS.md`;
  the kit gets a new `service.env` key or option when real work needs it.

## Consequences

- A fix to a kit script reaches every service at once.
- The kit assumes one service shape: a multi-module Maven reactor with one `*-container` module,
  an optional Helm chart and `MAJOR.MINOR.PATCH` versions (`kit/README.md`). A new shape needs
  a kit change, not a local copy.
- `kit/examples/projects/sample-service/` is the only template. It shows the shape of a project
  folder. A new project copies it once and then owns its own files.
