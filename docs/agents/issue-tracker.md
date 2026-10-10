# Issue tracker: local markdown

Specs and tickets live as markdown files in a `.scratch/` folder. A spec is also known as a PRD.

## Where the tracker lives

| Work on | Folder |
|---|---|
| The harness itself (kit, standards, gate, skills) | `.scratch/<feature-slug>/` at the repository root |
| One service | `projects/<name>/.scratch/<feature-slug>/` |

Put a change to a service in that service's project folder, not at the root. The tickets of a
service then stay beside its `CODEBASE.md`, `GLOSSARY.md` and `docs/adr/`.

## Conventions

- Use one folder per feature: `.scratch/<feature-slug>/`.
- Write the spec to `.scratch/<feature-slug>/spec.md`.
- Write one file per ticket: `.scratch/<feature-slug>/issues/<NN>-<slug>.md`. Number the tickets
  from `01`. Never put all tickets in one file.
- Record the state in a `Status:` line near the top of each ticket and entry file. The
  vocabulary and the close-out are below.
- Record blockers in a `Blocked by: NN, NN` line near the top, or `Blocked by: None`.
- Append comments and conversation history to the bottom of the file, under a `## Comments`
  heading.

## Status line

Every ticket and every entry file (`spec.md`) has one `Status:` line near the top. The first
word is the state. Text after an em dash is free text: a date, a commit, a PR, an ADR number.
`Status: done — commit abc123` and `**Status:** done — commit abc123` are both valid.

The state is one word from this closed set. A word outside the set is a bug, not a new state.

| Scope | Open states | Terminal states |
|---|---|---|
| Ticket | the five triage roles in `triage-labels.md` | `done`, `wontfix` |
| Entry file | `open`, or a triage role | `closed` |

- `done` — the work landed. The free text links the evidence: a commit, a PR or an ADR.
- `wontfix` — the work does not happen in this effort. The free text gives the reason in one
  line. If the work moves to a new effort, name the new folder.
- `closed` — the folder is closed out (see below). The free text gives the date and points to
  the permanent home of the outcome.

## Close-out

A folder is **working state**. It is not a home for knowledge. Close the folder out when its
spec has shipped, or when the effort stops. A folder with open tickets and no commit for 60 days
is **stale**: review it for close-out.

1. **Move the durable outcome to its permanent home.** For the harness, this is `docs/adr/`,
   `standards/` or `kit/`. For a service, this is the project's `docs/adr/`, `GLOSSARY.md`,
   `CODEBASE.md` or `acceptance-tests/`. Anything that an agent must find later lives there, not
   in the folder.
2. **Give every ticket a terminal state**: `done` with its evidence, or `wontfix` with its
   reason. If a ticket still matters, move it to a new folder and set `wontfix — carried to
   <path>` here.
3. **Set the entry file to `Status: closed — <YYYY-MM-DD>`.** Add one line that points to the
   permanent homes of step 1.
4. **Keep the folder where it is.** ADRs link to `.scratch/` paths. Do not delete, move or
   rename a closed folder. Git history is the archive.

Do not reopen a closed folder. Start a new folder for new work on the same subject, and link
back to the closed folder.

A folder is closed when this command lists none of its tickets:

```sh
grep -rLE '^\*{0,2}Status:\*{0,2} *`?(done|wontfix)\b' --include='*.md' \
  .scratch/*/issues projects/*/.scratch/*/issues
```

Run from the repository root, the same command lists every open ticket in the workspace.

## When a skill says "publish to the issue tracker"

Create a new file under the right `.scratch/<feature-slug>/` folder (see the table at the top).
Create the folder if it does not exist.

## When a skill says "fetch the relevant ticket"

Read the file at the given path. The user normally gives the path or the ticket number.
