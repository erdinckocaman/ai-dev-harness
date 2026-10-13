#!/usr/bin/env bash
#
# new-project.sh — create the project folder projects/<name>/ of one Spring Boot Maven service
# from the kit's example project, kit/examples/projects/sample-service/. The new-project skill
# drives it; its SKILL.md says what the agent does around it.
#
# The script:
#   1. stops when the repository is not the top folder of a git repository with a root pom.xml;
#   2. discovers the service.env values from the repository content (the pom.xml files, the
#      @SpringBootApplication class, the application configuration, k8s/helm/, origin/HEAD),
#      and leaves a value empty, with a finding, when it cannot find it;
#   3. runs the fit check: what the kit scripts do not support in this repository;
#   4. creates each file of the example that is absent in projects/<name>/: service.env is
#      written from the discovered values, the example's identity (name, source repository,
#      mainline, port) is replaced, and the sample service's own suites, gates, remote targets
#      and glossary terms are left out. GLOSSARY.md, docs/adr/ and .scratch/ start empty. It
#      never overwrites a file, and it never runs git.
#
# Usage:
#   new-project.sh [--dry-run] [--name <project>] <repository path>
#
#   <repository path>   The service's source repository (a leading ~/ is expanded).
#   --dry-run           Discover, check and report; write nothing.
#   --name <project>    The project folder name. Default: the project whose service.env names
#                       this repository, else the repository folder name.
#
# The projects folder is projects/ of the harness that holds this script.
# Exit status: 0 done, 1 stopped before any write, 2 usage error, 3 a write failed (a second
# run creates what is still absent).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
HARNESS_ROOT="$(cd "$SCRIPT_DIR/../../../.." && pwd -P)"
EXAMPLE="$HARNESS_ROOT/kit/examples/projects/sample-service"
PROJECTS_DIR="$HARNESS_ROOT/projects"
# The one service.env parser and key list (service_env_get, service_env_var).
# shellcheck source=../../../../kit/scripts/lib/service-env.sh
source "$HARNESS_ROOT/kit/scripts/lib/service-env.sh"
# The root version, read as set-version.sh reads it (pom_root_version).
# shellcheck source=../../../../kit/scripts/lib/pom.sh
source "$HARNESS_ROOT/kit/scripts/lib/pom.sh"

usage() {
  sed -n '/^# Usage:/,/^# Exit status/p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

usage_error() {
  echo "error: $*" >&2
  echo >&2
  usage >&2
  exit 2
}

stop() {
  echo "stopped: $*" >&2
  echo "Nothing was written." >&2
  exit 1
}

write_failed() {
  echo "error: $*" >&2
  echo "A second run creates what is still absent." >&2
  exit 3
}

# A YAML or properties value without its trailing comment, its trailing spaces and its quotes.
clean_value() {
  sed -E 's/[[:space:]]+#.*$//; s/[[:space:]]+$//; s/^["'\'']//; s/["'\'']$//'
}

# --- Arguments --------------------------------------------------------------------------------

dry_run=0
name=""
repo_arg=""
while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) dry_run=1; shift ;;
    --name)
      [ $# -ge 2 ] || usage_error "--name requires a project name"
      name="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    -*) usage_error "unknown option: $1" ;;
    *)
      [ -z "$repo_arg" ] || usage_error "more than one repository: $repo_arg, $1"
      repo_arg="$1"; shift ;;
  esac
done
[ -n "$repo_arg" ] || usage_error "no repository path"
if [ -n "$name" ]; then
  case "$name" in
    */*|.*|*[[:space:]]*) usage_error "invalid project name: '$name' (expected a folder name)" ;;
  esac
fi
[ -f "$EXAMPLE/service.env" ] || stop "no example project at $EXAMPLE"

# --- The repository ---------------------------------------------------------------------------

case "$repo_arg" in
  "~/"*) repo="$HOME/${repo_arg#"~/"}" ;;
  *) repo="$repo_arg" ;;
esac
[ -d "$repo" ] || stop "no repository at $repo_arg."
repo="$(cd "$repo" && pwd -P)"
[ "$(git -C "$repo" rev-parse --show-toplevel 2>/dev/null)" = "$repo" ] ||
  stop "$repo is not the top folder of a git repository."
[ -f "$repo/pom.xml" ] || stop "$repo has no root pom.xml: it is not a Maven service."

# The SOURCE_REPO of a service.env, as the kit scripts read it.
source_repo_of() {
  service_env_get "$1" SOURCE_REPO
}

is_this_repo() {
  [ -n "$1" ] && [ -d "$1" ] && [ "$(cd "$1" && pwd -P)" = "$repo" ]
}

# --- Discovery --------------------------------------------------------------------------------
# Every value comes from the repository content. A value that cannot be found stays empty, and
# a finding says why and which tool needs it.

findings=()
finding() { findings+=("$1"); }

# The root pom's own <artifactId>: the first one outside the <parent> block.
pom_own() {
  awk -v tag="$1" '
    /<parent>/ { in_parent = 1 }
    in_parent { if (/<\/parent>/) in_parent = 0; next }
    match($0, "<" tag ">[^<]+</" tag ">") {
      print substr($0, RSTART + length(tag) + 2, RLENGTH - 2 * length(tag) - 5); exit
    }
  ' "$repo/pom.xml"
}
root_artifact_id="$(pom_own artifactId)"
[ -n "$root_artifact_id" ] ||
  finding "\`ROOT_ARTIFACT_ID\` is empty: the root \`pom.xml\` has no \`<artifactId>\` of its own. \`set-version.sh\` needs it."
root_version=""
[ -z "$root_artifact_id" ] || root_version="$(pom_root_version "$repo/pom.xml" "$root_artifact_id")"

# The modules that hold a @SpringBootApplication class under src/main ("." is the root).
mains=()
while IFS= read -r file; do
  mains+=("${file#"$repo"/}")
done < <(find "$repo" \( -name target -o -name .git -o -name node_modules \) -prune -o \
  -type f \( -name '*.java' -o -name '*.kt' \) -path '*/src/main/*' -print0 2>/dev/null |
  xargs -0 grep -lE '^[[:space:]]*@SpringBootApplication' 2>/dev/null | LC_ALL=C sort)

module_of() {
  case "$1" in
    src/main/*) echo . ;;
    *) echo "${1%%/src/main/*}" ;;
  esac
}

modules=()
for file in ${mains[@]+"${mains[@]}"}; do
  module="$(module_of "$file")"
  case " ${modules[*]-} " in *" $module "*) ;; *) modules+=("$module") ;; esac
done

container_module=""
if [ ${#modules[@]} -eq 1 ]; then
  container_module="${modules[0]}"
elif [ ${#modules[@]} -gt 1 ]; then
  containers=()
  for module in "${modules[@]}"; do
    case "$module" in *-container) containers+=("$module") ;; esac
  done
  if [ ${#containers[@]} -eq 1 ]; then
    container_module="${containers[0]}"
  else
    finding "\`CONTAINER_MODULE\` is empty: ${#modules[@]} modules hold a \`@SpringBootApplication\` class (${modules[*]}). \`run-local.sh\` needs the one it launches."
  fi
else
  finding "\`CONTAINER_MODULE\` and \`MAIN_CLASS\` are empty: no \`@SpringBootApplication\` class under \`src/main\`. \`run-local.sh\` needs both."
fi

main_class=""
service_name=""
service_port=""
if [ -n "$container_module" ]; then
  classes=()
  for file in "${mains[@]}"; do
    [ "$(module_of "$file")" = "$container_module" ] || continue
    file="$(basename "$file")"
    classes+=("${file%.*}")
  done
  if [ ${#classes[@]} -eq 1 ]; then
    main_class="${classes[0]}"
  else
    finding "\`MAIN_CLASS\` is empty: ${#classes[@]} classes carry \`@SpringBootApplication\` in \`$container_module\`. \`run-local.sh --stop\` needs it."
  fi

  if [ "$container_module" = . ]; then
    service_name="$root_artifact_id"
    resources="src/main/resources"
    finding "A single-module service: \`CONTAINER_MODULE\` is \`.\`, the root project, which \`run-local.sh\` launches with \`mvn -pl .\`; the kit assumes a multi-module reactor."
  else
    service_name="$(basename "$container_module")"
    service_name="${service_name%-container}"
    resources="$container_module/src/main/resources"
  fi

  # server.port of the module's base configuration, as written: the first YAML document's
  # server: block (or a flat server.port key), else application.properties.
  port_raw=""
  port_file=""
  for file in application.yml application.yaml application.properties; do
    [ -f "$repo/$resources/$file" ] || continue
    case "$file" in
      *.properties)
        port_raw="$(sed -n -E 's/^[[:space:]]*server\.port[[:space:]]*[=:][[:space:]]*//p' \
          "$repo/$resources/$file" | head -n 1 | clean_value)" ;;
      *)
        port_raw="$(awk '
          /^---/ { if (content) exit; next }
          /^[[:space:]]*(#|$)/ { next }
          { content = 1 }
          /^[^[:space:]]/ {
            in_server = ($0 ~ /^server:[[:space:]]*(#.*)?$/)
            child = 0
            if ($0 ~ /^server\.port:/) { sub(/^server\.port:[[:space:]]*/, ""); print; exit }
            next
          }
          in_server {
            match($0, /^[[:space:]]+/)
            if (!child) child = RLENGTH
            if (RLENGTH == child && $0 ~ /^[[:space:]]+port:/) {
              sub(/^[[:space:]]+port:[[:space:]]*/, ""); print; exit
            }
          }
        ' "$repo/$resources/$file" | clean_value)" ;;
    esac
    if [ -n "$port_raw" ]; then
      port_file="$resources/$file"
      break
    fi
  done
  if [ -z "$port_raw" ]; then
    service_port=8080
  elif [[ "$port_raw" =~ ^[0-9]+$ ]]; then
    service_port="$port_raw"
  elif [[ "$port_raw" =~ ^\$\{[A-Za-z0-9_.-]+:([0-9]+)\}$ ]]; then
    service_port="${BASH_REMATCH[1]}"
    finding "\`SERVICE_PORT\` is \`$service_port\`, the default of \`server.port: $port_raw\` in \`$port_file\`: an environment that sets the variable moves the port."
  else
    finding "\`SERVICE_PORT\` is empty: \`server.port\` in \`$port_file\` is \`$port_raw\`, not a literal port. \`run-local.sh\` and \`acceptance-tests/environments/local.env\` need it."
  fi
fi

charts=()
for dir in "$repo"/k8s/helm/*/; do
  [ -d "$dir" ] && charts+=("$(basename "$dir")")
done
helm_chart=""
if [ ${#charts[@]} -eq 1 ]; then
  helm_chart="${charts[0]}"
elif [ ${#charts[@]} -gt 1 ]; then
  finding "\`HELM_CHART\` is empty: \`k8s/helm/\` holds ${#charts[@]} charts (${charts[*]})."
fi

default_branch="$(git -C "$repo" symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null || true)"
default_branch="${default_branch#origin/}"
[ -n "$default_branch" ] ||
  finding "\`DEFAULT_BRANCH\` is empty: the repository has no \`origin/HEAD\` (\`git remote set-head origin --auto\` sets it). The commit check of \`kit/WORKFLOW.md\` needs it."

home_physical="$(cd "$HOME" 2>/dev/null && pwd -P || echo "$HOME")"
case "$repo" in
  "$home_physical"/*) source_repo="~/${repo#"$home_physical"/}" ;;
  *) source_repo="$repo" ;;
esac

# --- Fit check --------------------------------------------------------------------------------
# What the kit scripts do not support. The root version comes from pom_root_version, the
# reader of set-version.sh.

if [ -z "$root_version" ]; then
  finding "The root \`pom.xml\` has no \`<version>\` after its own \`<artifactId>\`: \`set-version.sh\` cannot read the current version."
elif ! [[ "$root_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  finding "The root version \`$root_version\` is not strict \`MAJOR.MINOR.PATCH\`: \`set-version.sh\` rejects it."
fi
for chart in ${charts[@]+"${charts[@]}"}; do
  chart_file="k8s/helm/$chart/Chart.yaml"
  [ -f "$repo/$chart_file" ] || continue
  app_version="$(sed -n -E 's/^[[:space:]]*appVersion:[[:space:]]*//p' "$repo/$chart_file" |
    head -n 1 | clean_value)"
  if [ -z "$app_version" ]; then
    finding "\`$chart_file\` has no \`appVersion\`: \`set-version.sh\` stops on it."
  elif [ -n "$root_version" ] && [ "$app_version" != "$root_version" ]; then
    finding "The Helm \`appVersion\` \`$app_version\` differs from the root version \`$root_version\` (\`$chart_file\`): a \`set-version.sh\` run rewrites it."
  fi
done

# --- The project name -------------------------------------------------------------------------
# An existing project whose service.env names this repository wins, so a second run completes
# that project.

name_source="given"
if [ -z "$name" ]; then
  for env_file in "$PROJECTS_DIR"/*/service.env; do
    [ -f "$env_file" ] || continue
    if is_this_repo "$(source_repo_of "$env_file")"; then
      name="$(basename "$(dirname "$env_file")")"
      name_source="its service.env names this repository"
      break
    fi
  done
fi
if [ -z "$name" ]; then
  name="$(basename "$repo")"
  name_source="the repository folder name"
fi
project_dir="$PROJECTS_DIR/$name"
case "$project_dir" in
  "$HARNESS_ROOT"/*) project_shown="${project_dir#"$HARNESS_ROOT"/}" ;;
  *) project_shown="$project_dir" ;;
esac

# An existing folder is completed only when it is this repository's project: service.env,
# written first, names the repository.
if [ -f "$project_dir/service.env" ]; then
  value="$(source_repo_of "$project_dir/service.env")"
  is_this_repo "$value" ||
    stop "$project_shown/service.env names another repository (${value:-none}). Choose another project name with --name."
elif [ -d "$project_dir" ] && [ -n "$(ls -A "$project_dir")" ]; then
  stop "$project_shown/ exists and has no service.env: it is not a service project. Choose another project name with --name."
fi

# --- Rendering --------------------------------------------------------------------------------

# The example's identity, replaced in the files that are copied from it.
example_value() {
  sed -n "s/^$1=//p" "$EXAMPLE/service.env" | head -n 1
}
example_name="$(sed -n '1s/^# \(.*\) — AGENTS\.md$/\1/p' "$EXAMPLE/AGENTS.md")"
[ -n "$example_name" ] || stop "the title of $EXAMPLE/AGENTS.md is not '# <name> — AGENTS.md'"
example_repo="$(example_value SOURCE_REPO)"
example_branch="$(example_value DEFAULT_BRANCH)"
example_port="$(example_value SERVICE_PORT)"

# The discovered values, in the svc_ variables of lib/service-env.sh. FILE_HEADER is never
# discovered: it stays empty.
service_env_clear
svc_repo="$source_repo"
svc_name="$service_name"
svc_port="$service_port"
svc_container_module="$container_module"
svc_main_class="$main_class"
svc_helm_chart="$helm_chart"
svc_root_artifact_id="$root_artifact_id"
svc_default_branch="$default_branch"

# The value of a service.env key: discovered for service.env, marked when empty elsewhere.
value_of() {
  local var
  var="$(service_env_var "$1")"
  if [ -n "$var" ]; then printf '%s\n' "${!var}"; fi
}
shown_value() {
  local value
  value="$(value_of "$1")"
  printf '%s\n' "${value:-<$1 not found>}"
}

render_service_env() {
  local line key
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in
      [A-Z]*=*) key="${line%%=*}"; printf '%s=%s\n' "$key" "$(value_of "$key")" ;;
      *) printf '%s\n' "$line" ;;
    esac
  done <"$EXAMPLE/service.env"
}

# Replaces each FROM_<n> with TO_<n> (literal text) in stdin.
replace() {
  awk '
    {
      for (n = 1; ("FROM_" n) in ENVIRON; n++) {
        from = ENVIRON["FROM_" n]; to = ENVIRON["TO_" n]
        if (from == "") continue
        out = ""; rest = $0
        while ((i = index(rest, from)) > 0) {
          out = out substr(rest, 1, i - 1) to
          rest = substr(rest, i + length(from))
        }
        $0 = out rest
      }
      print
    }
  '
}

identity() {
  FROM_1="$example_repo" TO_1="$source_repo" \
    FROM_2="mainline \`$example_branch\`" TO_2="mainline \`$(shown_value DEFAULT_BRANCH)\`" \
    FROM_3="$example_name" TO_3="$name" \
    replace
}

known_limits() {
  local text
  echo "Where this repository does not fit the kit, as the fit check of \`new-project\` found it:"
  echo
  for text in "${findings[@]}"; do
    printf '%s\n' "$text" | awk -v width=100 '{
      n = split($0, words, " "); line = "-"
      for (i = 1; i <= n; i++) {
        if (line != "-" && length(line) + 1 + length(words[i]) > width) { print line; line = " " }
        line = line " " words[i]
      }
      print line
    }'
  done
}

render_agents() {
  if [ ${#findings[@]} -eq 0 ]; then
    identity <"$EXAMPLE/AGENTS.md"
    return
  fi
  identity <"$EXAMPLE/AGENTS.md" | LIMITS="$(known_limits)" awk '
    skip && /^## / { skip = 0 }
    skip { next }
    { print }
    $0 == "## Known limits" { print ""; print ENVIRON["LIMITS"]; print ""; skip = 1 }
  ' | awk 'NR > 1 && prev == "" && $0 == "" { next } { print; prev = $0 }' |
    awk '{ lines[NR] = $0 } END { n = NR; while (n > 0 && lines[n] == "") n--; for (i = 1; i <= n; i++) print lines[i] }'
}

render_acceptance_readme() {
  awk '/^## Suites/ { exit } { print }' "$EXAMPLE/acceptance-tests/README.md" | identity
  cat <<'EOF'
## Suites

None yet. Add a suite under `suites/` when a change touches an HTTP endpoint (the close-out
table of `../../../kit/WORKFLOW.md`), and list it here.

| Suite | Covers |
|---|---|

## Gated blocks

None yet.

| Variable | Gate | Why |
|---|---|---|
EOF
}

# The example's glossary without its terms: a new service starts with an empty Language list.
render_glossary() {
  awk '/^## Language/ { exit } { print }' "$EXAMPLE/GLOSSARY.md" | identity
  cat <<'EOF'
## Language

None yet. Add a term when a discussion settles its meaning.
EOF
}

# render <example path>: the content of projects/<name>/<path> on stdout; exit 1 when the file
# belongs to the sample service and is not copied.
render() {
  case "$1" in
    service.env) render_service_env ;;
    AGENTS.md) render_agents ;;
    GLOSSARY.md) render_glossary ;;
    acceptance-tests/README.md) render_acceptance_readme ;;
    acceptance-tests/suites/*) return 1 ;;
    acceptance-tests/environments/common.env) grep '^#' "$EXAMPLE/$1" || true ;;
    acceptance-tests/environments/local.env)
      FROM_1="localhost:$example_port" TO_1="localhost:$(shown_value SERVICE_PORT)" \
        replace <"$EXAMPLE/$1" ;;
    acceptance-tests/environments/*) return 1 ;;
    *) identity <"$EXAMPLE/$1" ;;
  esac
}

write_file() {
  local dest="$project_dir/$1" tmp
  mkdir -p "$(dirname "$dest")" || write_failed "cannot create $(dirname "$dest")"
  tmp="$(mktemp "$(dirname "$dest")/.new-project.XXXXXX")" || write_failed "cannot write in $(dirname "$dest")"
  if ! render "$1" >"$tmp"; then
    rm -f "$tmp"
    write_failed "cannot render $1"
  fi
  chmod 644 "$tmp"
  mv "$tmp" "$dest" || write_failed "cannot create $dest"
}

# service.env goes first: it marks the folder as this repository's project, so a run that fails
# half-way is completed by the next one.
files=(service.env)
skipped=()
while IFS= read -r file; do
  [ "$file" = service.env ] && continue
  if render "$file" >/dev/null 2>&1; then files+=("$file"); else skipped+=("$file"); fi
done < <(cd "$EXAMPLE" && find . -type f ! -name '.DS_Store' | sed 's|^\./||' | LC_ALL=C sort)

# --- Report and write -------------------------------------------------------------------------

echo "repository: $repo"
echo "project: $name ($name_source)"
echo
echo "service.env values:"
render_service_env | sed -n 's/^\([A-Z_][A-Z_]*=\)/  \1/p'
echo
echo "root version (pom.xml): ${root_version:-<not found>}"
echo
echo "findings:"
if [ ${#findings[@]} -eq 0 ]; then
  echo "  none"
else
  for text in "${findings[@]}"; do echo "  - $text"; done
fi
echo
if [ $dry_run -eq 1 ]; then
  echo "files in $project_shown/ (dry run: nothing is written):"
else
  echo "files in $project_shown/:"
fi
for file in "${files[@]}"; do
  if [ -e "$project_dir/$file" ]; then
    echo "  exists   $file"
  elif [ $dry_run -eq 1 ]; then
    echo "  absent   $file"
  else
    write_file "$file"
    echo "  created  $file"
  fi
done
if [ -e "$project_dir/CODEBASE.md" ]; then
  echo "  exists   CODEBASE.md"
else
  echo "  absent   CODEBASE.md (the codebase-map skill writes it)"
fi
for file in ${skipped[@]+"${skipped[@]}"}; do
  echo "  left out $file (the sample service's own)"
done
echo
echo "Nothing is committed."
