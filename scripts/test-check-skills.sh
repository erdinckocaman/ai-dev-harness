#!/usr/bin/env bash
# Tests for check-skills.sh: builds small workspace trees in a temp folder and asserts the
# check's exit status for each. Usage: scripts/test-check-skills.sh
set -u
here="$(cd "$(dirname "$0")" && pwd)"
check="$here/check-skills.sh"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
pass=0 fail=0

# A workspace with one well-formed skill.
new_tree() {
  local t="$tmp/$1"
  mkdir -p "$t/.agents/skills/tdd" "$t/.claude/skills"
  printf -- '---\nname: tdd\ndescription: Test first.\n---\n\nWrite the test first.\n' \
    > "$t/.agents/skills/tdd/SKILL.md"
  ln -s ../../.agents/skills/tdd "$t/.claude/skills/tdd"
  echo "$t"
}

# expect <exit> <name> <tree>
expect() {
  local want="$1" name="$2" tree="$3" out got
  out="$("$check" "$tree" 2>&1)"; got=$?
  if [ "$got" -eq "$want" ]; then pass=$((pass + 1))
  else fail=$((fail + 1)); printf 'FAIL %s: want exit %s, got %s\n%s\n' "$name" "$want" "$got" "$out"
  fi
}

t=$(new_tree ok);            expect 0 "well-formed catalog passes" "$t"

t=$(new_tree empty); rm -rf "$t/.agents/skills/tdd" "$t/.claude/skills/tdd"
expect 1 "empty catalog fails" "$t"

t=$(new_tree nolink); rm "$t/.claude/skills/tdd"
expect 1 "skill without mirror link fails" "$t"

t=$(new_tree dangling); ln -s ../../.agents/skills/gone "$t/.claude/skills/gone"
expect 1 "dangling link fails" "$t"

t=$(new_tree elsewhere); mkdir -p "$t/other/tdd"; rm "$t/.claude/skills/tdd"
ln -s ../../other/tdd "$t/.claude/skills/tdd"
expect 1 "link to another target fails" "$t"

t=$(new_tree abslink); rm "$t/.claude/skills/tdd"; ln -s "$t/.agents/skills/tdd" "$t/.claude/skills/tdd"
expect 1 "absolute link fails" "$t"

t=$(new_tree copy); rm "$t/.claude/skills/tdd"; cp -R "$t/.agents/skills/tdd" "$t/.claude/skills/tdd"
expect 1 "copied directory instead of link fails" "$t"

t=$(new_tree badname); sed -i '' 's/^name: tdd/name: other/' "$t/.agents/skills/tdd/SKILL.md"
expect 1 "frontmatter name differs from folder fails" "$t"

t=$(new_tree project); mkdir -p "$t/projects/svc/.agents/skills/x" "$t/projects/svc/.claude/skills"
printf -- '---\nname: x\ndescription: X.\n---\n' > "$t/projects/svc/.agents/skills/x/SKILL.md"
expect 1 "project skill without mirror link fails" "$t"
ln -s ../../.agents/skills/x "$t/projects/svc/.claude/skills/x"
expect 0 "project skill with mirror link passes" "$t"

# Each line: a text that names an aos-only file, folder or skill.
while IFS= read -r bad; do
  t=$(new_tree "ref$((pass + fail))")
  printf '\n%s\n' "$bad" >> "$t/.agents/skills/tdd/SKILL.md"
  expect 1 "aos-only reference fails: $bad" "$t"
done <<'LINES'
Read WIKI.md first.
See PROJECTS.md for the catalog.
Read USER.md and IDENTITY.md.
Look in WORKPLACES.md.
Save it under wiki/concepts/.
Stage the file in raw/ first.
Write a note in daily/2026/.
Put notes in research/<topic>/.
Keep this knowledge in the aos PKB.
Run the `ingest` skill on the file.
Then run /wiki-sync.
Call the Skill tool with "note".
Use the `wayfinder` skill.
Use the `improve-codebase-architecture` skill.
Use the `jira-tasks` skill.
Use the `pilot-test-handoff` skill.
If not, tell the user to run `/setup-matt-pocock-skills`.
Run python3 ~/.claude/skills/jira-fetch/scripts/fetch_ticket.py KEY.
Then use the `prototype` skill.
LINES

# References to catalog skills pass.
t=$(new_tree goodrefs)
cat >> "$t/.agents/skills/tdd/SKILL.md" <<'TXT'

Use /tdd, then the `tdd` skill. Call the Skill tool with "tdd".
Keep notes in a scratch folder.
A daily stand-up is fine. Fetch `/users/${id}` and '/orders'.
TXT
expect 0 "catalog skill references pass" "$t"

# A skill that is not in the catalog fails, whatever its name (no allow-list).
for ref in 'Run the `set-version` skill.' 'Then run /new-project.' 'Call the Skill tool with "run-acceptance-tests".'; do
  t=$(new_tree "unknown$((pass + fail))")
  printf '\n%s\n' "$ref" >> "$t/.agents/skills/tdd/SKILL.md"
  expect 1 "skill outside the catalog fails: $ref" "$t"
done

# Absolute paths are not slash commands: a standard root folder named alone, at the end of a
# sentence or in backticks passes; an unknown /name still fails.
t=$(new_tree paths)
cat >> "$t/.agents/skills/tdd/SKILL.md" <<'TXT'

Write the log to /tmp, not to /etc. Look in `/var` and (/usr).
On macOS, /private holds /tmp; the user folder is under /Users or /home.
Scratch files go to /tmp/tdd-scratch/ and /opt.
TXT
expect 0 "standard root folders are not skill references" "$t"
t=$(new_tree unknown-command)
printf '\nThen run /deploy-everything.\n' >> "$t/.agents/skills/tdd/SKILL.md"
expect 1 "an unknown /name still fails" "$t"

printf '%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
