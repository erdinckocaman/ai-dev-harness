#!/usr/bin/env bash
# test-new-project.sh — tests for new-project.sh, the script of the new-project skill.
#
# Builds a throwaway harness (a git repository that holds a copy of kit/ and of this skill) and
# throwaway Maven repositories in a temp folder, runs the REAL script of the copy against them,
# and asserts its exit status, its report, the files it creates and the service.env values.
# Nothing outside the temp folder is written. Run after any change to the script or to
# kit/examples/projects/sample-service/:
#
#   bash .agents/skills/new-project/scripts/test-new-project.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
ROOT="$(cd "$SCRIPT_DIR/../../../.." && pwd -P)"

SANDBOX="$(cd "$(mktemp -d)" && pwd -P)"
trap 'rm -rf "$SANDBOX"' EXIT
export HOME="$SANDBOX/home"
REPOS="$HOME/src"
HARNESS="$SANDBOX/harness"
PROJECTS="$HARNESS/projects"
mkdir -p "$REPOS" "$HARNESS/.agents/skills"

git_q() { git -c user.name=test -c user.email=test@example.com "$@" >/dev/null 2>&1; }

cp -R "$ROOT/kit" "$HARNESS/kit"
cp -R "$ROOT/.agents/skills/new-project" "$HARNESS/.agents/skills/new-project"
git_q -C "$HARNESS" init -q
git_q -C "$HARNESS" add -A
git_q -C "$HARNESS" commit -q -m "harness"
HARNESS_HEAD="$(git -C "$HARNESS" rev-parse HEAD)"
NEW_PROJECT="$HARNESS/.agents/skills/new-project/scripts/new-project.sh"

pass=0
fail=0
report() {
  if [ "$1" = ok ]; then
    pass=$((pass + 1)); printf 'ok   %s\n' "$2"
  else
    fail=$((fail + 1)); printf 'FAIL %s\n     %s\n' "$2" "$3"
  fi
}

# Runs the script from the harness root; output in $out, exit status in $rc.
new_project() {
  out="$(cd "$HARNESS" && bash "$NEW_PROJECT" "$@" 2>&1)"
  rc=$?
}

expect_rc() {
  if [ "$rc" = "$1" ]; then report ok "$2"; else report fail "$2" "exit $rc, expected $1: $out"; fi
}

expect_out() {
  case "$out" in
    *"$1"*) report ok "$2" ;;
    *) report fail "$2" "output lacks '$1': $out" ;;
  esac
}

expect_no_out() {
  case "$out" in
    *"$1"*) report fail "$2" "output has '$1': $out" ;;
    *) report ok "$2" ;;
  esac
}

expect_file() {
  if [ -f "$1" ]; then report ok "$2"; else report fail "$2" "no file $1"; fi
}

expect_no_path() {
  if [ -e "$1" ]; then report fail "$2" "$1 exists"; else report ok "$2"; fi
}

# write_pom <file> <artifactId> <version> [<modules...>]
# A pom whose <parent> (Spring Boot) has its own artifactId and version, so the script must
# skip it to find the project's own.
write_pom() {
  local file="$1" artifact="$2" version="$3" modules=""
  shift 3
  if [ $# -gt 0 ]; then
    modules="    <packaging>pom</packaging>
    <modules>"
    for m in "$@"; do modules="$modules
        <module>$m</module>"; done
    modules="$modules
    </modules>"
  fi
  mkdir -p "$(dirname "$file")"
  cat >"$file" <<POM
<?xml version="1.0" encoding="UTF-8"?>
<project>
    <modelVersion>4.0.0</modelVersion>
    <parent>
        <groupId>org.springframework.boot</groupId>
        <artifactId>spring-boot-starter-parent</artifactId>
        <version>3.5.6</version>
    </parent>
    <groupId>com.example</groupId>
    <artifactId>$artifact</artifactId>
    <version>$version</version>
$modules
</project>
POM
}

# write_main <module dir> <class>
write_main() {
  mkdir -p "$1/src/main/java/com/example"
  printf 'package com.example;\n\n@SpringBootApplication\npublic class %s {\n}\n' "$2" \
    >"$1/src/main/java/com/example/$2.java"
}

# git_repo <dir> [<default branch>]: commit the tree; origin/HEAD names the branch.
git_repo() {
  git_q -C "$1" init -q
  git_q -C "$1" add -A
  git_q -C "$1" commit -q -m init
  if [ -n "${2:-}" ]; then
    git -C "$1" update-ref "refs/remotes/origin/$2" HEAD
    git -C "$1" symbolic-ref refs/remotes/origin/HEAD "refs/remotes/origin/$2"
  fi
}

# --- A single-module service ------------------------------------------------------------------

BILLING="$REPOS/billing"
write_pom "$BILLING/pom.xml" billing-service 1.4.2
write_main "$BILLING" BillingApplication
mkdir -p "$BILLING/src/main/resources"
printf 'spring.application.name=billing\nserver.port = 8085\n' \
  >"$BILLING/src/main/resources/application.properties"
git_repo "$BILLING" main

new_project "$BILLING"
expect_rc 0 "a run on a single-module service succeeds"
P="$PROJECTS/billing"
for f in AGENTS.md CLAUDE.md service.env GLOSSARY.md docs/adr/.gitkeep .scratch/.gitkeep \
  acceptance-tests/README.md acceptance-tests/environments/common.env \
  acceptance-tests/environments/local.env; do
  expect_file "$P/$f" "single module: the run creates $f"
  expect_out "created  $f" "single module: the report lists $f as created"
done
out="$(cat "$P/service.env")"
expect_out "SOURCE_REPO=~/src/billing
SERVICE_NAME=billing-service
SERVICE_PORT=8085
CONTAINER_MODULE=.
MAIN_CLASS=BillingApplication
HELM_CHART=
ROOT_ARTIFACT_ID=billing-service
DEFAULT_BRANCH=main" "single module: service.env holds the values of the repository"


out="$(cat "$P/AGENTS.md")"
expect_out "# billing — AGENTS.md" "AGENTS.md is titled with the project name"
expect_out "Source repository: \`~/src/billing\` (mainline \`main\`)" \
  "AGENTS.md names the source repository and its mainline"
expect_out "single-module service: \`CONTAINER_MODULE\` is \`.\`" \
  "Known limits records that the service is not a multi-module reactor"
if cmp -s "$P/CLAUDE.md" "$HARNESS/kit/examples/projects/sample-service/CLAUDE.md"; then
  report ok "CLAUDE.md is the example's pointer file"
else
  report fail "CLAUDE.md is the example's pointer file" "$(cat "$P/CLAUDE.md")"
fi
out="$(cat "$P/GLOSSARY.md")"
expect_out "# billing" "GLOSSARY.md is titled with the project name"
expect_out "## Language" "GLOSSARY.md has the Language section of the glossary format"
expect_no_out "**Item**" "the sample service's glossary terms are left out"
out="$(cat "$P/acceptance-tests/environments/local.env")"
expect_out "baseUrl=http://localhost:8085" "local.env targets the discovered port"
out="$(cat "$P/acceptance-tests/environments/common.env" "$P/acceptance-tests/README.md")"
expect_no_out "skipItem" "the sample service's gates are left out"
expect_no_out "## Fields asserted" "the sample service's asserted fields are left out"
expect_no_path "$P/acceptance-tests/suites" "the sample service's suites are left out"
expect_no_path "$P/acceptance-tests/environments/dev.env" "the sample service's dev target is left out"
expect_no_path "$P/CODEBASE.md" "the script leaves CODEBASE.md to the codebase-map skill"
if grep -rqiE 'orders|example\.com' "$P"; then
  report fail "no identity of the sample service is left" "$(grep -rniE 'orders|example\.com' "$P")"
else
  report ok "no identity of the sample service is left"
fi

out="$(git -C "$HARNESS" status --porcelain --untracked-files=all)"
expect_out "?? projects/billing/service.env" "the new files are untracked in the harness"
expect_no_out "A  " "nothing is staged"
if [ "$(git -C "$HARNESS" rev-parse HEAD)" = "$HARNESS_HEAD" ]; then
  report ok "the run makes no commit"
else
  report fail "the run makes no commit" "HEAD moved"
fi

out="$(cd "$HARNESS" && bash kit/scripts/set-version.sh --project billing 2>&1)"
expect_out "current version: 1.4.2" "the kit scripts read the new service.env"

# --- A multi-module service -------------------------------------------------------------------
# Two modules hold a @SpringBootApplication class; the *-container one is the service. A redis
# port comes before the server block, and a later profile document has its own server.port.

ORDERS="$SANDBOX/elsewhere/shop-orders"
write_pom "$ORDERS/pom.xml" shop-orders 2.0.0-SNAPSHOT shop-domain shop-container shop-tools
write_pom "$ORDERS/shop-domain/pom.xml" shop-domain 2.0.0-SNAPSHOT
write_main "$ORDERS/shop-container" ShopApplication
write_main "$ORDERS/shop-tools" ToolsApplication
mkdir -p "$ORDERS/shop-container/src/main/resources" "$ORDERS/k8s/helm/shop"
printf -- '---\nspring:\n  data:\n    redis:\n      port: 6379\nserver:\n  port: ${PORT:9010}\n---\nspring.config.activate.on-profile: dev\nserver:\n  port: 1\n' \
  >"$ORDERS/shop-container/src/main/resources/application.yml"
printf 'apiVersion: v2\nname: shop\nversion: 0.1.0\nappVersion: "1.9.0"\n' >"$ORDERS/k8s/helm/shop/Chart.yaml"
git_repo "$ORDERS" develop

new_project --dry-run "$ORDERS"
expect_rc 0 "a dry run on a multi-module service succeeds"
expect_out "project: shop-orders" "the dry run proposes the repository folder name"
expect_out "absent   AGENTS.md" "the dry run lists the files it would create"
expect_no_path "$PROJECTS/shop-orders" "a dry run writes nothing"

new_project --name shop "$ORDERS"
expect_rc 0 "a run on a multi-module service succeeds"
out="$(cat "$PROJECTS/shop/service.env")"
expect_out "SOURCE_REPO=$ORDERS
SERVICE_NAME=shop
SERVICE_PORT=9010
CONTAINER_MODULE=shop-container
MAIN_CLASS=ShopApplication
HELM_CHART=shop
ROOT_ARTIFACT_ID=shop-orders
DEFAULT_BRANCH=develop" "multi module: service.env holds the values of the repository"
out="$(cat "$PROJECTS/shop/AGENTS.md")"
expect_out "# shop — AGENTS.md" "--name names the project folder and its title"
expect_out "\`2.0.0-SNAPSHOT\` is not strict" "Known limits records a version that set-version.sh rejects"
expect_out "\`appVersion\` \`1.9.0\` differs" "Known limits records an appVersion that differs from the root version"
expect_out "the default of \`server.port: \${PORT:9010}\`" "Known limits records a port taken from a placeholder default"
expect_no_out "None yet." "Known limits replaces the example's text when the fit check finds something"

# --- A repository that fits the kit ----------------------------------------------------------

FIT="$REPOS/fit"
write_pom "$FIT/pom.xml" fit 3.1.0 fit-container
write_main "$FIT/fit-container" FitApplication
git_repo "$FIT" main
new_project "$FIT"
expect_rc 0 "a run on a repository that fits the kit succeeds"
expect_out "findings:
  none" "a repository that fits the kit has no findings"
out="$(cat "$PROJECTS/fit/AGENTS.md")"
expect_out "None yet." "a repository that fits the kit keeps the example's Known limits text"
out="$(cat "$PROJECTS/fit/service.env")"
expect_out "SERVICE_PORT=8080" "without server.port, SERVICE_PORT is the Spring Boot default"

# --- The root version, as set-version.sh reads it --------------------------------------------
# set-version.sh takes the first <version> after the root <artifactId>; a <version> written
# above it is not found, and the fit check says so.

EARLY="$REPOS/early-version"
mkdir -p "$EARLY"
cat >"$EARLY/pom.xml" <<'POM'
<project>
    <modelVersion>4.0.0</modelVersion>
    <groupId>com.example</groupId>
    <version>5.0.0</version>
    <artifactId>early-version</artifactId>
    <packaging>pom</packaging>
    <modules>
        <module>early-container</module>
    </modules>
</project>
POM
write_main "$EARLY/early-container" EarlyApplication
git_repo "$EARLY" main
new_project "$EARLY"
expect_rc 0 "a run on a repository whose root version precedes its artifactId succeeds"
expect_out "has no \`<version>\` after its own \`<artifactId>\`: \`set-version.sh\` cannot read the current version" \
  "the fit check reads the root version as set-version.sh does"
out="$(cd "$HARNESS" && bash kit/scripts/set-version.sh --project early-version 2>&1)"
expect_out "could not determine current version" "set-version.sh cannot read that root version either"

# service.env is read by kit/scripts/lib/service-env.sh: an owner edit with spaces after an
# older SOURCE_REPO line still names this repository, because the last line wins.
mv "$PROJECTS/fit" "$PROJECTS/fitting"
{
  printf 'SOURCE_REPO=%s\n' "$ORDERS"
  sed 's|^SOURCE_REPO=.*|  SOURCE_REPO =  ~/src/fit/  |' "$PROJECTS/fitting/service.env"
} >"$PROJECTS/fitting/service.env.new"
mv "$PROJECTS/fitting/service.env.new" "$PROJECTS/fitting/service.env"
new_project --dry-run "$FIT"
expect_rc 0 "a run on a repository whose service.env was edited by hand succeeds"
expect_out "project: fitting (its service.env names this repository)" \
  "the last, spaced SOURCE_REPO line names the repository"

# --- A second run ---------------------------------------------------------------------------

printf '\nAn owner edit.\n' >>"$P/AGENTS.md"
printf '\n**Invoice**:\nA request for payment.\n' >>"$P/GLOSSARY.md"
printf 'an owner note\n' >"$P/.scratch/.gitkeep"
rm "$P/acceptance-tests/environments/local.env"
snapshot() { (cd "$1" && find . -type f -exec shasum {} + | LC_ALL=C sort); }
new_project "$BILLING"
expect_rc 0 "a second run succeeds"
expect_out "project: billing (its service.env names this repository)" \
  "a second run finds the project whose service.env names the repository"
expect_out "exists   AGENTS.md" "a second run lists an existing file as existing"
expect_out "created  acceptance-tests/environments/local.env" "a second run creates a file that is absent"
if [ "$(tail -n 1 "$P/AGENTS.md")" = "An owner edit." ]; then
  report ok "an existing file is not overwritten"
else
  report fail "an existing file is not overwritten" "$(cat "$P/AGENTS.md")"
fi
if [ "$(tail -n 1 "$P/GLOSSARY.md")" = "A request for payment." ] &&
  [ "$(cat "$P/.scratch/.gitkeep")" = "an owner note" ]; then
  report ok "an existing GLOSSARY.md and .scratch/ file are not overwritten"
else
  report fail "an existing GLOSSARY.md and .scratch/ file are not overwritten" "$(cat "$P/GLOSSARY.md")"
fi
expect_out "exists   GLOSSARY.md" "a second run lists GLOSSARY.md as existing"

# --- Refusals -------------------------------------------------------------------------------

before="$(snapshot "$PROJECTS")"
new_project --name billing "$ORDERS"
expect_rc 1 "a run into the project of another repository stops"
expect_out "names another repository" "the stop message says the folder belongs to another repository"

mkdir -p "$PROJECTS/notes"
printf '# notes\n' >"$PROJECTS/notes/README.md"
before="$(snapshot "$PROJECTS")"
new_project --name notes "$ORDERS"
expect_rc 1 "a run into a folder without service.env stops"
if [ "$(snapshot "$PROJECTS")" = "$before" ]; then
  report ok "a stopped run writes nothing"
else
  report fail "a stopped run writes nothing" "the projects folder changed"
fi

mkdir -p "$REPOS/no-maven"
printf 'hello\n' >"$REPOS/no-maven/README.md"
git_repo "$REPOS/no-maven"
new_project "$REPOS/no-maven"
expect_rc 1 "a repository without a root pom.xml stops the script"
expect_out "pom.xml" "the stop message names the missing pom.xml"

mkdir -p "$SANDBOX/not-git"
write_pom "$SANDBOX/not-git/pom.xml" not-git 1.0.0
new_project "$SANDBOX/not-git"
expect_rc 1 "a folder that is not a git repository stops the script"
expect_no_path "$PROJECTS/no-maven" "a stopped run creates no project folder"

new_project
expect_rc 2 "a run without a repository is a usage error"
new_project --bogus "$BILLING"
expect_rc 2 "an unknown option is a usage error"

# --- A relative SOURCE_REPO -----------------------------------------------------------------
# A relative SOURCE_REPO is relative to the project folder, for new-project and the kit scripts.

mkdir -p "$PROJECTS/relative"
printf 'SOURCE_REPO=../../../home/src/billing\nROOT_ARTIFACT_ID=billing-service\n' \
  >"$PROJECTS/relative/service.env"
new_project --dry-run --name relative "$BILLING"
expect_rc 0 "a run into a project whose relative SOURCE_REPO names the repository succeeds"
out="$(cd "$HARNESS" && bash kit/scripts/set-version.sh --project relative 2>&1)"
expect_out "current version: 1.4.2" "the kit scripts resolve a relative SOURCE_REPO against the project folder"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
