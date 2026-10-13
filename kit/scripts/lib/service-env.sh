# service-env.sh — sourced by every kit script: find the service project and
# load its service.env.
#
# A script calls `load_service_env "<--project value or empty>" KEY...` after it
# has parsed its arguments. The project is projects/<name>/ of the harness: the
# --project value, or else the project whose folder holds the working directory.
# MS_KIT_PROJECTS_DIR moves projects/ for the kit tests (kit/scripts/test-check.sh)
# only; it is not a user setting, and the standards gate does not read it.
# Each KEY that follows must have a value in service.env.
#
# On return, project_name and project_dir are set, and each service.env key is
# in a lowercase svc_ variable (SOURCE_REPO -> svc_repo, see service_env_var).
# The lowercase names keep them apart from the uppercase keys that run-local.sh
# exports from a developer env file.
#
# service.env is parsed, never sourced, and this file is its only parser: the
# kit scripts, new-project.sh and the standards gate all read it here.
#   - One KEY=value per line; blank lines and # comment lines are skipped.
#   - Spaces around the key and around the value are dropped; no quotes.
#   - A key may appear twice: the last line wins.
#   - A value `~` or one that starts with `~/` starts at $HOME.
#   - A relative SOURCE_REPO or FILE_HEADER is relative to the project folder
#     (the folder of service.env); a trailing / of these paths is dropped.
# load_service_env stops the script on an unknown key or a line that is not
# KEY=value. service_env_get reads one key and skips such lines.

MS_KIT_SCRIPTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
MS_KIT_PROJECTS_DIR="${MS_KIT_PROJECTS_DIR:-$MS_KIT_SCRIPTS_DIR/../../projects}"
if [ -d "$MS_KIT_PROJECTS_DIR" ]; then
  MS_KIT_PROJECTS_DIR="$(cd "$MS_KIT_PROJECTS_DIR" && pwd -P)"
fi
SERVICE_ENV_KEYS="SOURCE_REPO SERVICE_NAME SERVICE_PORT CONTAINER_MODULE MAIN_CLASS HELM_CHART ROOT_ARTIFACT_ID DEFAULT_BRANCH FILE_HEADER"

# The svc_ variable that holds a service.env key; nothing for an unknown key.
service_env_var() {
  case "$1" in
    SOURCE_REPO)      echo svc_repo ;;
    SERVICE_NAME)     echo svc_name ;;
    SERVICE_PORT)     echo svc_port ;;
    CONTAINER_MODULE) echo svc_container_module ;;
    MAIN_CLASS)       echo svc_main_class ;;
    HELM_CHART)       echo svc_helm_chart ;;
    ROOT_ARTIFACT_ID) echo svc_root_artifact_id ;;
    DEFAULT_BRANCH)   echo svc_default_branch ;;
    FILE_HEADER)      echo svc_file_header ;;
  esac
}

# Sets every svc_ variable to the empty string.
service_env_clear() {
  local key
  for key in $SERVICE_ENV_KEYS; do
    printf -v "$(service_env_var "$key")" '%s' ""
  done
}

# Stops with exit 2, after the calling script's own usage when it has one.
service_env_fail() {
  echo "error: $*" >&2
  if declare -F usage >/dev/null; then
    echo >&2
    usage >&2
  fi
  exit 2
}

# service_env_split <line>: sets service_env_key and service_env_value, both
# trimmed, for a KEY=value line. Returns 1 for a blank or comment line, 2 for a
# line that is not KEY=value.
service_env_split() {
  local line="${1%$'\r'}"
  line="${line#"${line%%[![:space:]]*}"}"
  line="${line%"${line##*[![:space:]]}"}"
  case "$line" in
    ''|'#'*) return 1 ;;
    *=*) ;;
    *) return 2 ;;
  esac
  service_env_key="${line%%=*}"
  service_env_key="${service_env_key%"${service_env_key##*[![:space:]]}"}"
  service_env_value="${line#*=}"
  service_env_value="${service_env_value#"${service_env_value%%[![:space:]]*}"}"
  [ -n "$service_env_key" ] || return 2
}

# service_env_resolve <project dir> <key> <value>: prints the value as the
# scripts use it (~ for $HOME; a relative path key against the project folder).
service_env_resolve() {
  local dir="$1" key="$2" value="$3"
  case "$value" in
    "~") value="$HOME" ;;
    "~/"*) value="$HOME/${value#"~/"}" ;;
  esac
  case "$key" in
    SOURCE_REPO|FILE_HEADER)
      case "$value" in
        ''|/*) ;;
        *) value="$dir/$value" ;;
      esac
      while [ "${value%/}" != "$value" ] && [ "$value" != "/" ]; do value="${value%/}"; done
      ;;
  esac
  printf '%s\n' "$value"
}

# service_env_get <service.env> <KEY>: prints the resolved value of KEY, the
# last line wins; nothing when the key is absent. Other lines are not checked.
service_env_get() {
  local file="$1" want="$2" line value="" found=""
  [ -f "$file" ] || return 0
  while IFS= read -r line || [ -n "$line" ]; do
    service_env_split "$line" || continue
    if [ "$service_env_key" = "$want" ]; then
      value="$service_env_value"
      found=1
    fi
  done < "$file"
  [ -n "$found" ] || return 0
  service_env_resolve "$(dirname "$file")" "$want" "$value"
}

load_service_env() {
  local name="$1" projects_dir="$MS_KIT_PROJECTS_DIR" cwd rel file line key value var rc
  shift

  if [ -z "$name" ]; then
    cwd="$(pwd -P)"
    case "$cwd/" in
      "$projects_dir"/*/*)
        rel="${cwd#"$projects_dir"/}"
        name="${rel%%/*}"
        ;;
      *)
        service_env_fail "no project: pass --project <name>, or run from inside $projects_dir/<name>/"
        ;;
    esac
  fi

  case "$name" in
    */*|.*|'') service_env_fail "invalid project name: '$name' (expected a folder name under $projects_dir)" ;;
  esac
  project_name="$name"
  project_dir="$projects_dir/$name"
  [ -d "$project_dir" ] || service_env_fail "no such project: $project_dir"
  file="$project_dir/service.env"
  [ -f "$file" ] || service_env_fail "project '$name' has no service.env ($file)"

  service_env_clear

  while IFS= read -r line || [ -n "$line" ]; do
    rc=0
    service_env_split "$line" || rc=$?
    case "$rc" in
      1) continue ;;
      2) echo "error: not a KEY=value line in $file: ${line%$'\r'}" >&2; exit 2 ;;
    esac
    key="$service_env_key"
    var="$(service_env_var "$key")"
    [ -n "$var" ] || { echo "error: unknown key '$key' in $file" >&2; exit 2; }
    value="$(service_env_resolve "$project_dir" "$key" "$service_env_value")"
    printf -v "$var" '%s' "$value"
  done < "$file"

  for key in "$@"; do
    var="$(service_env_var "$key")"
    [ -n "$var" ] && [ -n "${!var}" ] || {
      echo "error: $file has no value for $key" >&2
      exit 2
    }
  done
}
