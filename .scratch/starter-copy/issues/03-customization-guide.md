# 03 — Customization guide

Status: done — `docs/customizing.md`
Blocked by: None

**What to build:** `docs/customizing.md`, linked from the README and from the "Where to look"
table of `AGENTS.md`. It lists every customization point of a copy: the file, what it controls,
and the check to run after a change. At least:

- `standards/guidelines/*.md` and `standards/GUIDELINES.md` (the rules and the routing table).
- `standards/gate-routes.txt` (the gate routes), then `bash standards/test-check-routes.sh`.
- `standards/checks/` (Checkstyle, the layer model, the commit-check limits), then
  `kit/scripts/test-check.sh`.
- `.agents/skills/` (add or remove a skill and its `.claude/skills/` link), then
  `scripts/check-skills.sh`.
- `kit/` (the service shape that ADR-0002 assumes).
- `AGENTS.md` invariants 5 and 6: starter-only rules that a copy can drop (ADR-0006).
- The `Status: draft` line of `standards/GUIDELINES.md`: the copy's owner approves the rules.
- `.mcp.json`.

- [x] Every path in the guide exists.
- [x] Every check named in the guide runs and passes on the starter.
