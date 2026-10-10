# Customizing your copy

This repository is a starter. You make one copy of it, and then you own every file in the copy
(`docs/adr/0006-starter-copied-once.md`). The starter sends no updates to your copy. "The
owner" in the documents of your copy is you.

This guide lists every file that you are expected to change, what it controls, and the check to
run after a change. Run every check from the repository root.

## Customization points

| File | What it controls | After a change, run |
|---|---|---|
| `standards/guidelines/*.md` | The rules: one file per topic, each rule with an ID and a tool tag | `bash standards/test-check-routes.sh` |
| `standards/GUIDELINES.md` | The routing table: which guidelines a task needs. Its section "Changing the standards" is the procedure for a new or changed rule | `bash standards/test-check-routes.sh` |
| `standards/gate-routes.txt` | The paths that the standards gate guards, and the guidelines each path needs. Its header gives the format | `bash standards/test-check-routes.sh`, then `bash hooks/test-standards-gate.sh` |
| `standards/checks/checkstyle.xml` | The Checkstyle rules of `check.sh` (line length, method length, naming, imports) | `bash kit/scripts/test-check.sh` |
| `standards/checks/architecture.properties` | The layer model of the ArchUnit rules: the layers, which layer may use which | `bash kit/scripts/test-check.sh` |
| `standards/checks/commit-check.conf` | The commit-message format and the migration file names | `bash kit/scripts/test-check.sh` |
| `kit/checks/pom.xml` | The Checkstyle and ArchUnit versions | `bash kit/scripts/test-check.sh` |
| `.agents/skills/<name>/` | The skill catalog. A new skill also needs its link `.claude/skills/<name>` → `../../.agents/skills/<name>` (`docs/adr/0004-skill-catalog-mirrored-by-symlink.md`) | `bash scripts/check-skills.sh`, then `bash scripts/test-check-skills.sh` |
| `scripts/check-skills.sh` (`foreign_re`) | The names that a skill must not use. They come from the knowledge base that the starter's skills came from. Remove a name if your own skills need it | `bash scripts/test-check-skills.sh` |
| `kit/` | The service shape that the scripts assume: a multi-module Maven reactor with one `*-container` module, an optional Helm chart, `MAJOR.MINOR.PATCH` versions (`kit/README.md`, ADR-0002) | `bash kit/scripts/test-check.sh`, then `bash .agents/skills/new-project/scripts/test-new-project.sh` |
| `AGENTS.md` | The invariants and the map that every agent session reads first | — |
| `.mcp.json` | The project MCP servers. Keep every secret in an environment variable, never in the file | `/mcp` in a Claude Code session |

A rule change touches two places: the text in `standards/guidelines/` and the value in
`standards/checks/`. A rule with a tool tag gets its check in the same change.

## Approve your standards

The starter's standards are a draft. Three files say so in a `Status: draft` line:
`standards/GUIDELINES.md`, `standards/checks/architecture.properties` and
`standards/checks/commit-check.conf`. Review the rules, change the ones that do not fit your
company, then remove the draft line from all three files.

The file header check is opt-in, because a header text belongs to an organization. To use it, set
`FILE_HEADER` in a project's `service.env` (`kit/scripts/README.md`, section "`check.sh`").

## Rules that bind the starter only

Two `AGENTS.md` invariants keep the starter neutral. Your copy can keep them or remove them:

- **Invariant 5, English only.** Write your copy in the language of your team.
- **Invariant 6, No employer content.** Your copy can name your company, its hosts, and its own
  standards.

All other invariants keep the workspace working. Keep them.
