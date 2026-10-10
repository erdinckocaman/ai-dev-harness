# Domain docs

How the engineering skills use the domain documentation of this workspace when they explore a
service or the harness.

## Read these before you explore

For work on a service, read its project folder first:

- **`projects/<name>/GLOSSARY.md`**: the vocabulary of that service's domain.
- **`projects/<name>/docs/adr/`**: read the ADRs that touch the area of your task.

For work on the harness itself, or when a project decision refers to one:

- **`GLOSSARY.md`** at the repository root: the vocabulary of the harness, if it has one.
- **`docs/adr/`** at the repository root: the decisions of the harness.

If one of these files does not exist, **continue without comment**. Do not report that it is
missing. Do not suggest that someone creates it. The `domain-modeling` skill creates these files
when a term or a decision is actually resolved.

## File structure

```text
/
|-- GLOSSARY.md              <- the harness vocabulary, if it has one
|-- docs/adr/                <- the decisions of the harness
`-- projects/
    `-- <name>/
        |-- GLOSSARY.md      <- the vocabulary of that service
        `-- docs/adr/        <- the decisions of that service
```

Each service has its own domain. The files of a project folder apply to that service only. The
root files apply to the harness and to every project. There is no context map file.

## Use the glossary's vocabulary

When your output names a domain concept (in a ticket title, a refactor proposal, a hypothesis, a
test name), use the term that `GLOSSARY.md` defines. Do not use a synonym that the glossary
tells you to avoid.

If the concept is not in the glossary, ask why. Either you invent language that the project does
not use (reconsider), or the glossary has a real gap (note it for the `domain-modeling` skill).

## Flag ADR conflicts

If your output contradicts an ADR, say so explicitly. Do not override the ADR silently:

> _Contradicts ADR-0003 (the gate keeps to path-certain rules), but worth reopening because..._
