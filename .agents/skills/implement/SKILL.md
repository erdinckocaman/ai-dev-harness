---
name: implement
description: "Implement a piece of work based on a spec or set of tickets."
disable-model-invocation: true
---

Implement the work described by the user in the spec or tickets.

For a service, follow `kit/WORKFLOW.md`: start in `projects/<name>/`, read the standards that `standards/GUIDELINES.md` routes the task to before the first source-file edit, and close the obligations of its close-out table in the same change.

Use /tdd where possible, at pre-agreed seams.

Compile regularly, run single test classes regularly (`kit/scripts/mvn-test.sh`), and run the full test suite once at the end.

Once done, use /code-review to review the work.

Commit your work to the current branch.
