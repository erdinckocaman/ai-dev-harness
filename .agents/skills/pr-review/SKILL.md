---
name: pr-review
description: Review a GitHub pull request against its ticket, report the findings grouped by severity and topic, and post the selected findings as line comments.
argument-hint: "<PR URL | owner/repo#number>"
disable-model-invocation: true
---

One pull request per run. Keep the run's files in `<scratchpad>/pr-<N>/`, where `<N>` is the
PR number. `gh`, `git fetch`, and a ticket fetch from an external tracker need network access:
run them with the sandbox off. The review is read-only: it reads the code and does not build or test it.

## Steps

1. Read the pull request.
   Run `gh pr view <PR> --json number,url,state,title,body,author,headRefName,headRefOid,baseRefName,files`.
   When the state is not `OPEN`, ask the owner before you continue.
   When `author.login` equals `gh api user --jq .login`, the PR is an **own PR**: the run ends
   with the report (step 7) and posts nothing.
   Save the existing review comments:
   `gh api repos/<owner>/<repo>/pulls/<N>/comments --paginate > existing-comments.json`.
   Completion criterion: the head branch, the head SHA, the base branch, the changed-file list,
   and the own-PR flag are known, and `existing-comments.json` exists.

2. Extract the candidate ticket keys from the head branch name.
   Match `[A-Za-z][A-Za-z0-9]+-[0-9]+` and write each key in upper case
   (`feature/abc-1234-inbox` → `ABC-1234`). Keep every key the branch holds. With no key
   in the branch, use the PR title. With no key in the title, ask the owner.
   Completion criterion: at least one candidate key.

3. Read the tickets and derive the requirements.
   For each candidate key, look for `projects/*/.scratch/<key-in-lower-case>*/` in the
   workspace. It holds the owner's spec and tickets for the key (`docs/agents/issue-tracker.md`).
   When the key also lives in an external tracker (Jira, GitHub Issues, …), fetch that ticket with
   the tool the owner uses for it, its comments and requirement-bearing attachments included.
   When no tool is available, ask the owner to paste the ticket. A key that resolves nowhere is
   not a ticket (`java21-1`): drop it and name it in the report. When no key resolves, ask the
   owner.
   A later comment can change or cancel what the description asks: the latest decision wins.
   Read a linked issue (parent, epic, linked story) only when the ticket text points to it for
   a requirement, or when the ticket is thin.
   The workspace spec is more precise than an external ticket. Where the two disagree, keep both
   texts and flag the difference in the report.
   Write `requirements.md`: one **requirement** per line, `R1`…`Rn`, each with the quoted
   ticket or spec line it comes from. With more than one key, prefix each ID with its key
   (`ABC-1234/R2`).
   Completion criterion: every acceptance criterion of every resolved ticket maps to a
   requirement, and every requirement quotes its source. A ticket with no testable requirement
   gets the note "thin ticket" in the report, and its R1 is the ticket summary.

4. Check out the PR head in an isolated worktree.
   Find the local clone: the `SOURCE_REPO` of a `projects/*/service.env` whose `origin` names the
   repository, else `gh repo clone <owner>/<repo> <scratchpad>/pr-<N>/clone`. Keep the matching project guide
   (`projects/<name>/AGENTS.md`) and its `CODEBASE.md`, when one exists, for step 5.

   ```bash
   git -C <clone> fetch origin <base> "+refs/pull/<N>/head:refs/remotes/origin/pr/<N>"
   git -C <clone> worktree add --detach <scratchpad>/pr-<N>/tree origin/pr/<N>
   ```

   Completion criterion: `git rev-parse HEAD` in the worktree equals `headRefOid`, and
   `git diff --name-only origin/<base>...HEAD` lists the same files as the PR.

5. Run three review passes in parallel.
   Collect the standards files first. Walk the routing table of `standards/GUIDELINES.md`
   against the changed paths and the kind of change, and take every file it routes to. The
   files that the standards gate (`hooks/standards-gate.sh`) demands for those paths are the
   minimum set. A repository that is not a workspace project uses its own standards files.

   Start the **defect pass** as a `general-purpose` sub-agent. Its prompt holds:
   - the diff command `git -C <scratchpad>/pr-<N>/tree diff origin/<base>...HEAD`;
   - the path of `requirements.md`, for the intended behavior;
   - the path of the project's `CODEBASE.md`, when one exists;
   - the brief: "Read-only review; do not build or run anything. Report, per topic:
     **Correctness** — wrong logic, an unhandled error, a race, a broken contract;
     **Security** — an authorization gap, an injection, a leaked secret or personal data;
     **Tests** — changed behavior with no test, or a test that does not assert the behavior it
     names. Give each finding a `path:line` on the PR head, its topic, and a one-line claim.
     Write 'none' under a topic with no finding. Under 400 words."

   While it works, run the `code-review` skill. Give it:
   - the fixed point `origin/<base>`, with the instruction that every git command runs as
     `git -C <scratchpad>/pr-<N>/tree`;
   - `requirements.md` as the spec;
   - the standards files collected above.

   Completion criterion: the Standards report, the Spec report, and the defect pass report are
   all back.

6. Verify and classify.
   Read the cited code in the worktree for every finding of the three passes. Drop a finding
   the code contradicts. Add each defect you find while reading under its topic.
   Give each requirement a status — met, partial, missing, or wrong — with the `path:line` that
   shows it.
   Give each kept finding six fields: an ID (`F1`…), a severity, a topic, an anchor, the
   evidence (the quoted requirement, standard rule, or code), and a fix.
   The findings of all passes go into one severity order on purpose: the reviewer needs one
   priority order, and the topic keeps the pass each finding came from.
   An **anchor** is a `path`, a `line`, and a `side` that a hunk of `gh pr diff <PR>` contains:
   `RIGHT` with the head line number for an added or context line, `LEFT` with the base line
   number for a deleted line. GitHub rejects a line comment outside the diff, so a finding
   with no such line (a missing requirement, a file the PR did not touch) has the anchor
   `body`.
   Compare each kept finding with `existing-comments.json`. A finding that an existing comment
   already makes — same path, within 3 lines, same claim — is **already raised**: keep it in
   the report with that mark.
   Completion criterion: every requirement has a status, every kept finding has all six
   fields, every line anchor is checked against the diff hunks, and every kept finding is
   checked against the existing comments.

7. Report.
   Write `report.md` and print it:
   - A header: the PR link, each ticket key and summary, the head SHA, the dropped keys, and
     the line "Read-only review: the code was not built or tested."
   - **Ticket coverage**: a table of `R` | requirement | status | evidence.
   - **Findings**: one `##` section per severity, most severe first. Inside each, one `###`
     section per topic. Each finding is one entry: `F3 — path:line — claim. Evidence. Fix.`
     Append `(already raised)` to a finding with that mark. Omit empty sections.
   - A last line with the finding count per severity.

   When `projects/*/.scratch/<key-in-lower-case>*/` exists, copy `report.md` there as
   `pr-<N>-review.md`, over any earlier copy. Commit only that file in the workspace with the
   message `pr-review: <KEY> PR #<N>`.
   For an own PR, go to step 10.
   Completion criterion: every kept finding appears once, and the copy is committed when the
   folder exists.

8. Ask which findings to post.
   Ask the owner to reply with finding IDs (`F1 F4`), `all`, or `none`. `all` means every kept
   finding that is not already raised.
   Wait for the reply.
   Completion criterion: the owner's reply names the set.

9. Post the selected findings as one review.
   Write `review.json`:

   ```json
   {
     "commit_id": "<headRefOid>",
     "event": "COMMENT",
     "body": "<one-line summary, then each selected finding whose anchor is body>",
     "comments": [
       {
         "path": "src/main/java/.../InboxService.java",
         "line": 42,
         "side": "RIGHT",
         "body": "**Major · Standards** — <claim>\n\n<evidence>\n\n<fix>"
       }
     ]
   }
   ```

   The body holds the summary and the body-anchored findings, the Ticket findings for missing,
   partial, and wrong requirements included. A finding that spans lines adds `start_line` and
   `start_side`. Write the comments in English. Post with
   `gh api repos/<owner>/<repo>/pulls/<N>/reviews --input review.json`.
   The event is `COMMENT`; use `APPROVE` or `REQUEST_CHANGES` only when the owner asks for it.
   A `422` rejects the whole review, and its message does not name the failing comment.
   Re-check each line anchor against the patches of
   `gh api repos/<owner>/<repo>/pulls/<N>/files --paginate`, move each comment whose line no
   hunk contains into the body, and post again. When the second post also returns `422`, move
   every line comment into the body, post, and tell the owner.
   Completion criterion: the API returns the review, and you report its `html_url`.

10. Remove the worktree: `git -C <clone> worktree remove <scratchpad>/pr-<N>/tree`, and
    `git -C <clone> update-ref -d refs/remotes/origin/pr/<N>`. Do this in every outcome,
    `none`, own PRs, and failed runs included.
    Completion criterion: `git -C <clone> worktree list` does not show the path.

## Severity

- **Critical** — merging ships wrong behavior, a security or data defect, or misses a core
  requirement.
- **Major** — a partial requirement, a broken documented standard, or changed behavior with no
  test. Fix before merge.
- **Minor** — a judgement call: a code smell, a naming or a design point.
- **Nit** — wording or style with no effect on behavior.

## Topics

- **Ticket** — a requirement that is partial, missing, or wrong; scope creep (behavior the
  ticket did not ask for).
- **Correctness** — wrong logic, an unhandled error, a race, a broken contract.
- **Security** — an authorization gap, an injection, a leaked secret or personal data.
- **Standards** — a broken rule of a documented standard; cite the file and the rule.
- **Design** — a smell from the `code-review` baseline.
- **Tests** — changed behavior without a test, or a test that does not assert it.
