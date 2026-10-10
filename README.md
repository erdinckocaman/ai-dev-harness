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
  .github/workflows/     CI: the five test scripts on every push and pull request
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

### 1. Make a copy

On GitHub, click "Use this template" → "Create a new repository". Choose the owner and the
visibility. The copy starts with a fresh history.

On another host, clone the starter and push it to a new, empty repository:

```bash
git clone https://github.com/erdinckocaman/ai-dev-harness.git my-harness
cd my-harness
git remote set-url origin <your repository URL>
git push -u origin main
```

Do not use a GitHub fork: a fork of a public repository cannot be private.

### 2. Install the tools

| Tool | Needed by |
|---|---|
| bash 3.2+ with `find`, `grep`, `sed`, `awk` | every script |
| git | `kit/scripts/check.sh` (the commit check), the `new-project` skill |
| python3 | `hooks/standards-gate.sh` (the standards gate) |
| JDK 21 or later | `kit/scripts/check.sh` (the ArchUnit runner); `mvn-test.sh` and `run-local.sh` pin JDK 21 |
| Maven | `kit/scripts/check.sh` (builds `kit/checks/`), `mvn-test.sh`, `run-local.sh` |
| [hurl](https://hurl.dev) 8.x | `kit/scripts/run-suite.sh` (the acceptance suites) |
| lsof | `kit/scripts/run-local.sh` (the port check; skipped when absent) |
| [Claude Code](https://claude.com/claude-code) | runs the standards gate hooks |

`mvn-test.sh` and `run-local.sh` find the JDK with `/usr/libexec/java_home`, so they run on
macOS only today (`kit/README.md`).

### 3. Set the context7 key

`.mcp.json` connects the `context7` MCP server, which serves current library documentation. It
reads the key from the environment. Set it before you start the agent:

```bash
export CONTEXT7_API_KEY=<your key>
```

### 4. Start Claude Code at the root

Run `claude` at the root of your copy. Trust the folder, and approve the project MCP server
`context7`. Then `/hooks` shows the standards gate hooks, and `/mcp` shows `context7` connected.

### 5. Run the tests

Run each test from the root. Each one ends with its pass and fail count.

```bash
bash hooks/test-standards-gate.sh
bash scripts/test-check-skills.sh
bash standards/test-check-routes.sh
bash .agents/skills/new-project/scripts/test-new-project.sh
bash kit/scripts/test-check.sh
```

The first run of `kit/scripts/test-check.sh` builds `kit/checks/` with Maven and downloads its
dependencies.

### 6. Add your first service

Clone the service repository on your machine. In a Claude Code session at the root, run:

```text
/new-project <path to the service repository>
```

The skill creates `projects/<name>/` from the kit's example project and fills `service.env`
from the repository. It leaves every change uncommitted for your review.

### 7. Customize the copy

Follow `docs/customizing.md`. Approve or change the standards first: they start as a draft.

## The standards gate runs under Claude Code only

`.claude/settings.json` connects `hooks/standards-gate.sh` as Claude Code hooks. The gate blocks
an edit in a service repository until the agent has read the guidelines for that path. Codex,
opencode and other tools do not load these hooks. Under those tools, only the `AGENTS.md`
invariant asks the agent to read the guidelines first, and nothing blocks an edit.

## License

[MIT](LICENSE)
