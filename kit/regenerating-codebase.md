# Regenerating CODEBASE.md

A service project's `CODEBASE.md` is a semantic summary that an agent regenerates by analyzing
the source repository (not a deterministic script). This procedure lives outside `CODEBASE.md`
on purpose: steps 4 to 6 are guards against a sloppy regeneration, and a guard stored inside the
regenerated artifact can be overwritten by the very mistake it protects against.

Run it after structural changes to the source repository, or on demand ("refresh
CODEBASE.md"). The source repository is `SOURCE_REPO` and the container module is
`CONTAINER_MODULE` in the project's `service.env`.

1. Inspect the source repository: root `pom.xml` modules/properties, each module's `pom.xml` and
   `src` package tree, the container module's bootstrap class and `resources` (profiles, i18n,
   logback), `Dockerfile`, and `k8s/`.
2. Rewrite the project's `CODEBASE.md` to match what you find, in this section layout: Overview,
   Where to start for common tasks, Build/test/run, Configuration management, Module layout,
   Keeping this file current. "Where to start" comes before the reference sections: it is the
   step-shaped part. Above Overview keep the title `# <project> — CODEBASE.md`, a short intro, and
   the bullets **Source repository** (with its mainline, `DEFAULT_BRANCH`) and **Domain
   language** / **Standards**.
3. Keep it a **structural/operational map only** — domain language stays in `GLOSSARY.md` and
   standards in the standards guide; link to them rather than restating.
4. When the project has a `docs/deployment.md`, keep the pointer to it in the Kubernetes bullet.
   It cannot be re-derived from the source repository (it covers cluster access from your
   machine), so a regeneration that only mirrors the repository would silently drop it.
5. **Hold the length at about 1,500 words.** Each module gets one table row: packages, key types
   and traps, owning ADR. The narrative of a mechanism (how a write path, a race guard or a stream
   works) belongs in the ADR that decided it, under a **How it is built** heading; the map carries
   a pointer to that section. When the analysis finds a mechanism with no ADR home, add the
   section to its ADR instead of growing the map. The bound holds for an incremental edit too: a
   change that adds to the map adds a pointer, not a narrative, and removes what went stale.
6. **Cache only what the repo cannot confess.** Keep the gotchas no config states (the JDK pin,
   a database account the deploy needs, the stale-jar reactor trap, a pom gap), and drop one when
   the repository fixes it. Leave inventories to the environment: the version number, workflow
   names, Helm files, migration file lists and env-var counts go stale and are one `ls` away.
