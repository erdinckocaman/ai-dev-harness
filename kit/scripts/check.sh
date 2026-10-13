#!/usr/bin/env bash
#
# check.sh — run the mechanical checks of the standards against a service repository.
#
# The checks run from the harness, with no change to the service's pom.xml
# (docs/adr/0005-build-checks-run-from-the-harness.md):
#   - Checkstyle with standards/checks/checkstyle.xml, on src/main/java and src/test/java of
#     every module;
#   - the ArchUnit rules of kit/checks/ with standards/checks/architecture.properties, on the
#     compiled classes (target/classes) of every module;
#   - the commit check with standards/checks/commit-check.conf, over the commits
#     origin/<DEFAULT_BRANCH>..HEAD and the files they change (the working tree included);
#   - the file header check, only when service.env sets FILE_HEADER.
# Every finding is one line that starts with the rule ID of the guideline it breaks.
#
# The limits and patterns live in standards/checks/, not in this script. Tool versions live in
# kit/checks/pom.xml; the first run builds that module with Maven (network for the download).
#
# This script lives in the workspace, not in the code repo. Runs on the macOS bash 3.2.
#
# Usage:
#   check.sh [--project <name>] [--repo <path>]
#
# Exit status: 0 no violation; 1 a violation; 2 usage error; 3 a check could not run (a
# missing tool, no compiled or stale classes, no origin/<DEFAULT_BRANCH>). A check that cannot
# run never counts as passed.

set -uo pipefail
# Character ranges such as [a-z] in the patterns mean ASCII letters.
export LC_COLLATE=C

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/service-env.sh
source "$SCRIPT_DIR/lib/service-env.sh"

HARNESS_DIR="$(cd "$SCRIPT_DIR/../.." && pwd -P)"
CONFIG_DIR="$HARNESS_DIR/standards/checks"
MODULE_DIR="$HARNESS_DIR/kit/checks"
CLASSPATH_FILE="$MODULE_DIR/target/classpath.txt"

die() {
  echo "error: $*" >&2
  exit 2
}

usage() {
  cat <<'EOF'
Usage:
  check.sh [--project <name>] [--repo <path>]

  --project  The service project (a folder under projects/, with a service.env).
             Default: the project the working directory is in.
  --repo     The source repository. Default: SOURCE_REPO of the project's service.env.

Runs Checkstyle, the ArchUnit rules, the commit check (origin/<DEFAULT_BRANCH>..HEAD) and,
when service.env sets FILE_HEADER, the file header check. Compile the service first.

Exit: 0 no violation, 1 a violation, 2 usage error, 3 a check could not run.
EOF
}

# --- Parse arguments ---------------------------------------------------------

project=""
repo=""
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
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "error: unknown argument: $1" >&2
      echo >&2
      usage >&2
      exit 2
      ;;
  esac
done

load_service_env "$project" DEFAULT_BRANCH
repo="${repo:-$svc_repo}"
[ -n "$repo" ] || service_env_fail "no source repository: set SOURCE_REPO in $project_dir/service.env or pass --repo"
[ -d "$repo" ] || die "source repository not found: $repo"
repo="$(cd "$repo" && pwd -P)"

# --- Results -----------------------------------------------------------------

violated=""     # the checks that found a violation
not_run=""      # the checks that could not run

# section <title> — prints a section heading.
section() {
  echo
  echo "== $1 =="
}

# finish <check> <violation count> — prints the result line of a check.
finish() {
  if [ "$2" -gt 0 ]; then
    echo "$1: $2 violation(s)"
    violated="$violated, $1"
  else
    echo "$1: passed"
  fi
}

# cannot_run <check> <reason> — records that a check could not run.
cannot_run() {
  echo "$1: could not run: $2"
  not_run="$not_run, $1"
}

# read_conf <file> <key> — prints the value of KEY in a KEY=value file; fails when absent.
read_conf() {
  local line
  line="$(grep -E "^$2=" "$1" | tail -n 1)" || return 1
  printf '%s\n' "${line#*=}"
}

# relative <path> — the path relative to the source repository.
relative() {
  if [ "$1" = "$repo" ]; then
    echo .
  else
    echo "${1#"$repo/"}"
  fi
}

# --- Prerequisites -----------------------------------------------------------

echo "Checking $repo (project $project_name)"

# The source folders: src/main/java and src/test/java of every module, build output pruned.
main_dirs=()
test_dirs=()
while IFS= read -r dir; do
  case "$dir" in
    */src/main/java) main_dirs+=("$dir") ;;
    */src/test/java) test_dirs+=("$dir") ;;
  esac
done < <(find "$repo" \( -name target -o -name node_modules -o -name '.*' ! -path "$repo" \) -prune \
  -o -type d \( -path '*/src/main/java' -o -path '*/src/test/java' \) -print | sort)

# java_tools_problem — prints why the JVM tools cannot run; nothing when they can.
java_tools_problem() {
  local version major
  command -v java > /dev/null || { echo "java not found on PATH"; return; }
  version="$(java -version 2>&1 | sed -n 's/.*version "\([^"]*\)".*/\1/p' | head -n 1)"
  major="${version%%.*}"
  case "$major" in
    ''|*[!0-9]*) echo "cannot read the java version ('$version')"; return ;;
  esac
  [ "$major" -ge 21 ] || echo "java $version is too old: the checks need java 21 or later"
}

# build_module — compiles kit/checks/ and writes its classpath, when either is out of date.
build_module() {
  local log
  if [ -s "$CLASSPATH_FILE" ] && [ -d "$MODULE_DIR/target/classes" ] \
    && [ -z "$(find "$MODULE_DIR/pom.xml" "$MODULE_DIR/src" -newer "$CLASSPATH_FILE" -print | head -n 1)" ]; then
    return 0
  fi
  command -v mvn > /dev/null || { echo "mvn not found on PATH: it builds kit/checks"; return 1; }
  log="$(mktemp)"
  echo "Building kit/checks (first run, or the module changed) ..."
  if ! mvn -q -B -f "$MODULE_DIR/pom.xml" compile dependency:build-classpath \
    -Dmdep.outputFile="$CLASSPATH_FILE" > "$log" 2>&1; then
    rm -f "$CLASSPATH_FILE"
    tail -n 20 "$log"
    echo "(full Maven log: $log)"
    return 1
  fi
  # The plugin leaves an unchanged file as it is; the stamp must be newer than the sources.
  touch "$CLASSPATH_FILE"
  rm -f "$log"
}

tools_problem="$(java_tools_problem)"
if [ -z "$tools_problem" ] && ! build_module; then
  tools_problem="kit/checks could not be built (see above)"
fi
tool_classpath=""
[ -n "$tools_problem" ] || tool_classpath="$MODULE_DIR/target/classes:$(cat "$CLASSPATH_FILE")"

# --- Checkstyle --------------------------------------------------------------

run_checkstyle() {
  local out status count
  section "Checkstyle (standards/checks/checkstyle.xml)"
  [ -z "$tools_problem" ] || { cannot_run Checkstyle "$tools_problem"; return; }
  [ ${#main_dirs[@]} -gt 0 ] || { cannot_run Checkstyle "no src/main/java folder in $repo"; return; }
  out="$(java -cp "$tool_classpath" com.puppycrawl.tools.checkstyle.Main \
    -c "$CONFIG_DIR/checkstyle.xml" "${main_dirs[@]}" ${test_dirs[@]+"${test_dirs[@]}"} 2>&1)"
  status=$?
  count="$(printf '%s\n' "$out" | grep -c '^\[ERROR\] ')"
  if [ "$status" -ne 0 ] && [ "$count" -eq 0 ]; then
    printf '%s\n' "$out" | tail -n 20
    cannot_run Checkstyle "Checkstyle stopped with exit $status"
    return
  fi
  # "[ERROR] <path>:<line>:<col>: <message> [<RULE-ID>]" -> "<RULE-ID>  <path>:<line>:<col>: <message>"
  printf '%s\n' "$out" | grep '^\[ERROR\] ' \
    | sed -E 's/^\[ERROR\] (.*) \[([A-Z]+-[0-9]+)\]$/\2  \1/' \
    | while IFS= read -r line; do
        case "$line" in
          *"  $repo/"*) printf '%s  %s\n' "${line%%  *}" "${line#*  "$repo"/}" ;;
          *) printf '%s\n' "$line" ;;
        esac
      done
  finish Checkstyle "$count"
}

# --- ArchUnit ----------------------------------------------------------------

# stale_classes <module> — prints the main sources that have no class file newer than them.
stale_classes() {
  local module="$1" src cls
  while IFS= read -r src; do
    cls="$module/target/classes/${src#"$module/src/main/java/"}"
    cls="${cls%.java}.class"
    if [ ! -f "$cls" ] || [ "$src" -nt "$cls" ]; then
      relative "$src"
    fi
  done < <(find "$module/src/main/java" -name '*.java' ! -name package-info.java ! -name module-info.java)
}

run_archunit() {
  local dir module class_dirs=() stale="" found out status
  section "ArchUnit (kit/checks, standards/checks/architecture.properties)"
  [ -z "$tools_problem" ] || { cannot_run ArchUnit "$tools_problem"; return; }
  [ ${#main_dirs[@]} -gt 0 ] || { cannot_run ArchUnit "no src/main/java folder in $repo"; return; }
  for dir in "${main_dirs[@]}"; do
    module="${dir%/src/main/java}"
    if [ ! -d "$module/target/classes" ]; then
      cannot_run ArchUnit "no compiled classes in $(relative "$module/target/classes"): compile the service first (mvn compile)"
      return
    fi
    found="$(stale_classes "$module")"
    [ -z "$found" ] || stale="$stale$found"$'\n'
    class_dirs+=("$module/target/classes")
  done
  if [ -n "$stale" ]; then
    printf '%s' "$stale" | head -n 5 | sed 's/^/  newer than its class: /'
    cannot_run ArchUnit "the classes are stale: compile the service first (mvn compile)"
    return
  fi
  # slf4j-simple comes with Checkstyle; warn level keeps ArchUnit's INFO lines out.
  out="$(java -Dorg.slf4j.simpleLogger.defaultLogLevel=warn -cp "$tool_classpath" \
    dev.aidevharness.checks.ArchitectureCheck \
    "$CONFIG_DIR/architecture.properties" "${class_dirs[@]}" 2>&1)"
  status=$?
  out="$(printf '%s\n' "$out" | grep -v '^SLF4J')"
  case "$status" in
    0) finish ArchUnit 0 ;;
    1)
      printf '%s\n' "$out" | grep -v '^ArchUnit: '
      finish ArchUnit "$(printf '%s\n' "$out" | grep -c '^[A-Z][A-Z]*-[0-9]*  ')"
      ;;
    *)
      printf '%s\n' "$out" | tail -n 20
      cannot_run ArchUnit "the ArchUnit runner stopped with exit $status"
      ;;
  esac
}

# --- Commit check ------------------------------------------------------------

conf="$CONFIG_DIR/commit-check.conf"
commit_count=0

# report <rule> <text> — prints one commit-check violation.
report() {
  echo "$1  $2"
  commit_count=$((commit_count + 1))
}

# check_message <sha> — CORE-11 to CORE-13 on one commit message.
check_message() {
  local sha="$1" short msg header subject n=0 line parents
  short="$(git -C "$repo" rev-parse --short "$sha")"
  msg="$(git -C "$repo" log -1 --format=%B "$sha")"
  header="$(printf '%s\n' "$msg" | head -n 1)"
  parents="$(git -C "$repo" rev-list --parents -n 1 "$sha" | wc -w)"
  if [ "$parents" -gt 2 ] || [[ $header == 'Revert "'* ]] || [[ $header =~ $fixup ]]; then
    return
  fi
  if [[ $header =~ $header_pattern ]]; then
    subject="${header#*: }"
    [[ $subject == [[:lower:]]* ]] || report CORE-12 "$short \"$header\": the subject does not start with a lowercase letter"
    [[ $subject != *. ]] || report CORE-12 "$short \"$header\": the subject ends with a period"
  else
    report CORE-11 "$short \"$header\": not <type>(<scope>): <subject>, type one of $types"
  fi
  [ "${#header}" -le "$header_max" ] \
    || report CORE-12 "$short \"$header\": the header has ${#header} characters (max $header_max)"
  while IFS= read -r line; do
    n=$((n + 1))
    if [ "$n" -eq 2 ] && [ -n "$line" ]; then
      report CORE-13 "$short: line 2 of the message is not blank"
    elif [ "$n" -gt 2 ] && [ "${#line}" -gt "$body_max" ] && [[ $line != *://* ]]; then
      report CORE-13 "$short: body line $n has ${#line} characters (max $body_max)"
    fi
  done < <(printf '%s\n' "$msg")
}

# changed_files <merge-base> <diff filter> — the paths that differ from the merge base in the
# working tree, plus the untracked files when the filter takes added files.
changed_files() {
  git -C "$repo" diff --name-only --diff-filter="$2" "$1" --
  case "$2" in
    *A*) git -C "$repo" ls-files --others --exclude-standard ;;
  esac
}

in_migration_dir() {
  case "/$1" in
    */"$migration_dir"/*) return 0 ;;
  esac
  return 1
}

check_files() {
  local base="$1" path hit status old name_pattern="^($migration_name)$"
  # CORE-14: conflict markers in every file that the branch changes. A "=======" line counts
  # only inside an open "<<<<<<< " block: alone, it is a Markdown heading underline.
  while IFS= read -r path; do
    [ -f "$repo/$path" ] || continue
    while IFS= read -r hit; do
      report CORE-14 "$path:$hit: conflict marker"
    done < <(grep -n -I -E '^(<<<<<<< |>>>>>>> |=======$)' "$repo/$path" | awk -F: '
      { text = substr($0, length($1) + 2) }
      text ~ /^<<<<<<< / { open = 1; print $1; next }
      text ~ /^>>>>>>> / { open = 0; print $1; next }
      open { print $1 }')
  done < <(changed_files "$base" ACMR | sort -u)
  # DB-11: the name of every added migration.
  while IFS= read -r path; do
    in_migration_dir "$path" || continue
    [[ ${path##*/} =~ $name_pattern ]] \
      || report DB-11 "$path: a migration is named V<yyyyMMddHHmm>__<snake_case>.sql"
  done < <(changed_files "$base" A | sort -u)
  # DB-12: no change, rename or delete of a versioned migration that the default branch has.
  while IFS="$(printf '\t')" read -r status old _; do
    in_migration_dir "$old" || continue
    case "${old##*/}" in
      V*) report DB-12 "$old: a migration of the default branch is changed (${status:0:1}); add a new one" ;;
    esac
  done < <(git -C "$repo" diff --name-status -M --diff-filter=MDR "$base" --)
}

run_commit_check() {
  local ref="origin/$svc_default_branch" base sha count=0
  section "Commit check ($ref..HEAD, standards/checks/commit-check.conf)"
  command -v git > /dev/null || { cannot_run "Commit check" "git not found on PATH"; return; }
  git -C "$repo" rev-parse --git-dir > /dev/null 2>&1 \
    || { cannot_run "Commit check" "$repo is not a git repository"; return; }
  if ! git -C "$repo" rev-parse --verify -q "refs/remotes/$ref^{commit}" > /dev/null; then
    cannot_run "Commit check" "no $ref in $repo: run git fetch origin, or fix DEFAULT_BRANCH in service.env"
    return
  fi
  base="$(git -C "$repo" merge-base "$ref" HEAD)" \
    || { cannot_run "Commit check" "HEAD has no common commit with $ref"; return; }
  types="$(read_conf "$conf" COMMIT_TYPES)" \
    && scope="$(read_conf "$conf" COMMIT_SCOPE)" \
    && header_max="$(read_conf "$conf" HEADER_MAX)" \
    && body_max="$(read_conf "$conf" BODY_MAX)" \
    && fixup="$(read_conf "$conf" FIXUP_HEADER)" \
    && migration_dir="$(read_conf "$conf" MIGRATION_DIR)" \
    && migration_name="$(read_conf "$conf" MIGRATION_NAME)" \
    || { cannot_run "Commit check" "a key is missing in $conf"; return; }
  header_pattern="^($types)(\\($scope\\))?!?: .+$"
  while IFS= read -r sha; do
    count=$((count + 1))
    check_message "$sha"
  done < <(git -C "$repo" rev-list --reverse "$ref..HEAD")
  echo "($count commit(s) since $ref)"
  check_files "$base"
  finish "Commit check" "$commit_count"
}

# --- File header (opt-in) ----------------------------------------------------

run_header_check() {
  local file="$svc_file_header" header lines dir src count=0
  section "File header (FILE_HEADER in service.env)"
  if [ -z "$file" ]; then
    echo "File header: off (service.env sets no FILE_HEADER)"
    return
  fi
  [ -f "$file" ] || { cannot_run "File header" "FILE_HEADER file not found: $file"; return; }
  header="$(cat "$file")"
  [ -n "$header" ] || { cannot_run "File header" "FILE_HEADER file is empty: $file"; return; }
  lines="$(printf '%s\n' "$header" | wc -l | tr -d ' ')"
  echo "(every Java source starts with the $lines line(s) of $file)"
  for dir in ${main_dirs[@]+"${main_dirs[@]}"} ${test_dirs[@]+"${test_dirs[@]}"}; do
    while IFS= read -r src; do
      if [ "$(head -n "$lines" "$src")" != "$header" ]; then
        echo "HEADER  $(relative "$src"): does not start with the file header"
        count=$((count + 1))
      fi
    done < <(find "$dir" -name '*.java' | sort)
  done
  finish "File header" "$count"
}

# --- Run ---------------------------------------------------------------------

run_checkstyle
run_archunit
run_commit_check
run_header_check

echo
if [ -n "$violated" ]; then
  echo "Violations: ${violated#, }."
  [ -z "$not_run" ] || echo "Could not run: ${not_run#, }."
  exit 1
fi
if [ -n "$not_run" ]; then
  echo "Could not run: ${not_run#, }. No result for these checks."
  exit 3
fi
echo "All checks passed."
exit 0
