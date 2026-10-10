# ai-dev-harness

A workspace for AI-driven development of Spring Boot services with an AI coding agent (Claude
Code, Codex, opencode, …). The service repositories stay as the team keeps them; the agent
instructions, standards, acceptance tests and helper scripts live here.

```
ai-dev-harness/
  AGENTS.md  CLAUDE.md  README.md
  kit/                   shared scripts, workflow, acceptance-test conventions, the example
                         project (examples/projects/sample-service/) and the ArchUnit runner
  standards/             GUIDELINES.md (routing table), guidelines/, build-check configs
  hooks/                 standards-gate.sh and its test
  docs/agents/           issue tracker, triage labels, domain docs
  docs/adr/              decisions of the harness itself
  .agents/skills/        the skill catalog (real files)
  .claude/skills/        symlinks to .agents/skills/
  .claude/settings.json  the standards gate hooks
  scripts/               harness checks (check-skills.sh and its test)
  projects/<name>/       one folder per service: AGENTS.md, CLAUDE.md, service.env,
                         CODEBASE.md, GLOSSARY.md, docs/adr/, acceptance-tests/, .scratch/;
                         the code stays in its own repository
```

Start an agent session at the root of this repository. The agent reads `AGENTS.md`, then the
project folder of the service it works on.

The kit came from the standalone `ms-kit` repository.

## Make your own copy

This repository is a starter. Make one copy of it for your company or for yourself, then adapt
the copy: the standards, the gate routes, the build checks and the skills. The starter sends no
updates to a copy (`docs/adr/0006-starter-copied-once.md`). `docs/customizing.md` lists every
file to change and the check to run after each change.

## The standards gate runs under Claude Code only

`.claude/settings.json` connects `hooks/standards-gate.sh` as Claude Code hooks. The gate blocks
an edit in a service repository until the agent has read the guidelines for that path. Codex,
opencode and other tools do not load these hooks. Under those tools, only the `AGENTS.md`
invariant asks the agent to read the guidelines first, and nothing blocks an edit.

## License

[MIT](LICENSE)
