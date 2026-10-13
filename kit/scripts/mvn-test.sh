#!/usr/bin/env bash
#
# mvn-test.sh — run selected test classes of one module of a microservice
# and print an unambiguous per-class summary from the surefire XML reports.
#
# Why: surefire's console output misleads on @Nested-only classes. It prints
# "Tests run: 0 ... in <TopClass>" for the outer class (which has no direct
# tests) next to the real counts, which it labels with the nested classes'
# @DisplayName. `mvn -q` prints nothing at all on success. This script reads
# the <testsuite> totals instead, one line per top-level class, and treats a
# run that executed zero tests as a failure.
#
# Verified on surefire 3.5.5: a bare -Dtest=Foo runs Foo's @Nested classes, but
# only while no filter entry names a method (Foo#m). Each entry is therefore
# paired with Foo$* (see "Build the filter"); a prefix wildcard (Foo*) is not
# used, because it also matches other classes, such as FooBarTest.
#
# This script lives in the workspace, not in the code repo.
#
# Usage:
#   mvn-test.sh [--project <name>] [--repo <path>] [--am] <module> <Class>[#method] [<Class>...]
#
#   <module>  A module directory name (e.g. orders-domain), a path
#             relative to the repo root, or a Maven selector (:artifactId).
#   --am      Also build the modules <module> depends on, so it does not
#             compile against stale sibling jars in the local repository.
#
# Exit status: 0 all selected tests passed (at least one ran); 1 a test or the
# build failed; 2 usage error; 3 the build passed but no test ran.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/service-env.sh
source "$SCRIPT_DIR/lib/service-env.sh"

# The JDK the build pins; newer JDKs can break annotation processors such as Lombok.
MS_KIT_JDK="${MS_KIT_JDK:-21}"

die() {
  echo "error: $*" >&2
  exit 2
}

usage() {
  cat <<'EOF'
Usage:
  mvn-test.sh [--project <name>] [--repo <path>] [--am] <module> <Class>[#method] [<Class>...]

  <module>   Module directory name (e.g. orders-domain), path relative
             to the repo root, or Maven selector (:artifactId).
  --am       Also build the modules <module> depends on (avoids stale sibling jars).
  --project  The service project (a folder under projects/, with a service.env).
             Default: the project the working directory is in.
  --repo     The source repository. Default: SOURCE_REPO of the project's service.env.

Exit: 0 passed, 1 test or build failure, 2 usage error, 3 no test ran.
EOF
}

# --- Parse arguments ---------------------------------------------------------

project=""
repo=""
also_make=0
positional=()
while [ $# -gt 0 ]; do
  case "$1" in
    --project)
      [ $# -ge 2 ] || die "--project requires a name argument"
      project="$2"
      shift 2
      ;;
    --project=*)
      project="${1#--project=}"
      shift
      ;;
    --repo)
      [ $# -ge 2 ] || die "--repo requires a path argument"
      repo="$2"
      shift 2
      ;;
    --repo=*)
      repo="${1#--repo=}"
      shift
      ;;
    --am)
      also_make=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    -*)
      die "unknown option: $1 (see --help)"
      ;;
    *)
      positional+=("$1")
      shift
      ;;
  esac
done

if [ ${#positional[@]} -lt 2 ]; then
  usage >&2
  exit 2
fi

load_service_env "$project" SOURCE_REPO
repo="${repo:-$svc_repo}"
[ -f "$repo/pom.xml" ] || die "no pom.xml in repo: $repo"

module="${positional[0]}"
classes=("${positional[@]:1}")

# --- Resolve the module ------------------------------------------------------

case "$module" in
  :*)
    selector="$module"
    ;;
  */*)
    [ -f "$repo/$module/pom.xml" ] || die "no pom.xml in module path: $module"
    selector="$module"
    ;;
  *)
    matches=$(cd "$repo" && find . -type d -name "$module" -not -path '*/target/*' \
      -exec test -f '{}/pom.xml' ';' -print | sed 's|^\./||')
    [ -n "$matches" ] || die "no module directory named '$module' in $repo"
    [ "$(printf '%s\n' "$matches" | wc -l | tr -d ' ')" -eq 1 ] \
      || die "module name '$module' is ambiguous: $(echo $matches)"
    selector="$matches"
    ;;
esac

# --- Build the filter --------------------------------------------------------

# A bare Class pulls in its @Nested classes only while no filter entry names a
# method; once one does, Class and Class#method both miss the nested classes.
# So every entry is paired with an explicit Class$* entry.
patterns=()
for entry in "${classes[@]}"; do
  cls="${entry%%#*}"
  case "$entry" in
    *\$*) patterns+=("$entry") ;;
    *#*)  patterns+=("$entry" "$cls\$*#${entry#*#}") ;;
    *)    patterns+=("$entry" "$entry\$*") ;;
  esac
done
test_filter=$(IFS=,; echo "${patterns[*]}")

# --- Run ---------------------------------------------------------------------

JAVA_HOME=$(/usr/libexec/java_home -v "$MS_KIT_JDK" 2>/dev/null) \
  || die "JDK $MS_KIT_JDK not found (/usr/libexec/java_home -v $MS_KIT_JDK); newer JDKs break Lombok"
export JAVA_HOME

work=$(mktemp -d "${TMPDIR:-/tmp}/mvn-test.XXXXXX")
log="$work/mvn.log"
marker="$work/start"
touch "$marker"
# Report files are matched by mtime against the marker; avoid a same-second tie.
sleep 1

mvn_args=(-B -pl "$selector")
if [ "$also_make" -eq 1 ]; then mvn_args+=(-am); fi
mvn_args+=(test "-Dtest=$test_filter" -Dsurefire.failIfNoSpecifiedTests=false)

echo "mvn ${mvn_args[*]}"
echo "(JDK $MS_KIT_JDK, repo $repo, full log: $log)"
set +e
(cd "$repo" && mvn "${mvn_args[@]}") >"$log" 2>&1
mvn_status=$?
set -e

# --- Summarize the surefire reports written by this run ----------------------

# Prints one attribute of the <testsuite> element of a surefire XML report.
suite_attr() {
  sed -n '/<testsuite /{
s/.*<testsuite [^>]* '"$2"'="\([^"]*\)".*/\1/p
q
}' "$1"
}

total=0; failed=0; errored=0; skipped=0
reports=$(find "$repo" -path '*/target/surefire-reports/TEST-*.xml' -newer "$marker" | sort)

echo
printf '%-7s %-6s %-6s %-7s %s\n' TESTS FAIL ERROR SKIPPED CLASS
for report in $reports; do
  t=$(suite_attr "$report" tests); f=$(suite_attr "$report" failures)
  e=$(suite_attr "$report" errors); s=$(suite_attr "$report" skipped)
  name=$(suite_attr "$report" name)
  printf '%-7s %-6s %-6s %-7s %s\n' "$t" "$f" "$e" "$s" "${name##*.}"
  total=$((total + t)); failed=$((failed + f)); errored=$((errored + e)); skipped=$((skipped + s))

  # For a nested test, classname holds the @Nested class's @DisplayName.
  awk '
    /<testcase / {
      name = $0; sub(/.*<testcase name="/, "", name); sub(/".*/, "", name)
      cls = $0;  sub(/.* classname="/, "", cls);     sub(/".*/, "", cls)
    }
    /<(failure|error)[ >]/ { kind = ($0 ~ /<failure/) ? "FAILED " : "ERROR  "; print "  " kind cls " > " name }
  ' "$report"
done
echo "-------"
printf '%-7s %-6s %-6s %-7s %s\n' "$total" "$failed" "$errored" "$skipped" TOTAL

if [ "$skipped" -gt 0 ]; then
  echo "note: skipped is not a pass — Testcontainers tests skip without Docker."
fi

if [ "$mvn_status" -ne 0 ]; then
  echo
  echo "BUILD FAILED (mvn exit $mvn_status). Errors from the log:"
  errors=$(grep -E '^\[ERROR\]' "$log" \
    | grep -vE '^\[ERROR\] *$|Re-run Maven|full stack trace|Help 1|For more information|^\[ERROR\] -> ' || true)
  if [ -n "$errors" ]; then
    printf '%s\n' "$errors" | head -30
  else
    tail -30 "$log"
  fi
  exit 1
fi

if [ "$total" -eq 0 ]; then
  echo
  echo "NO TEST RAN: the build passed, but no selected test executed."
  echo "Check the class names and the module (filter: $test_filter, module: $selector)."
  exit 3
fi

echo
echo "PASSED: $total tests."
