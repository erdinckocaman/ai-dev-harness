# 02 — README: make a copy and the first run

Status: done — README section "Make your own copy", steps 1–7
Blocked by: 01

**What to build:** A README section for a new owner, in this order:

1. Make a copy: "Use this template", or a clone pushed to a new repository (ADR-0006). A GitHub
   fork of a public repository cannot be private.
2. Install the prerequisites: Java, Maven, hurl, python3 (the gate), git, lsof. Name what needs
   each tool. Read the tool checks in `kit/scripts/*.sh` and `hooks/standards-gate.sh` for the
   full list, and name only tools that a script uses.
3. Set `CONTEXT7_API_KEY` (`.mcp.json`).
4. Start Claude Code at the root and approve the project hooks and the MCP server.
5. Run the five test scripts.
6. Add the first service with the `new-project` skill.
7. Continue with the customization guide (ticket 03).

- [x] Every tool in the list is used by a script, and every tool that a script needs is in the list.
- [x] Every command in the section runs on a clean clone.
