#!/usr/bin/env bash
#
# run-local.sh — start a Spring Boot microservice locally with an env file.
#
# Loads KEY=VALUE pairs from an env file (skipping comments and blank lines),
# exports them, then launches the service's container module via Maven. The
# repository, module, port and main class come from the project's service.env.
#
# This script lives in the workspace, not in the code repo.
#
# Usage:
#   run-local.sh                                  Use defaults (env file + local profile)
#   run-local.sh --project sample-service      Name the project (default: the one the
#                                                 working directory is in)
#   run-local.sh --env ~/.ms-kit/local.env        Use a specific env file
#   run-local.sh --profile dev                    Use a specific Spring profile
#   run-local.sh --repo /some/other/checkout      Use a different source repo
#   run-local.sh --stop                           Stop a locally running service
#   run-local.sh --help                           Show this help

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/service-env.sh
source "$SCRIPT_DIR/lib/service-env.sh"

# The JDK the build pins; newer JDKs can break annotation processors such as Lombok.
MS_KIT_JDK="${MS_KIT_JDK:-21}"

# ---------------------------------------------------------------------------
# Defaults
# ---------------------------------------------------------------------------
# One developer env file serves every service: they share one database and
# each sets its own schema.
PROJECT=""
REPO=""
ENV_FILE="${MS_KIT_ENV_FILE:-$HOME/.ms-kit/local.env}"
PROFILE="local"
ACTION="run"

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------
usage() {
  cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Start a Spring Boot microservice locally by loading variables from an env file.

Options:
  --project <name>  The service project (a folder under MS_KIT_PROJECTS_DIR, with a
                    service.env). Default: the project the working directory is in.
  --env <path>      Path to the env file (KEY=VALUE pairs).
                    Default: \$MS_KIT_ENV_FILE, else ~/.ms-kit/local.env
  --profile <name>  Spring profile to activate (default: local)
  --repo <path>     Source repository path (default: SOURCE_REPO of service.env)
  --stop            Stop the locally running service (and its Maven parent), then exit.
                    Neither the repo nor a build is needed; the env file is only read to
                    resolve SERVER_PORT.
  --help            Show this help

Examples:
  $(basename "$0") --project sample-service
  $(basename "$0") --env ~/.ms-kit/local.env --profile dev
  $(basename "$0") --stop
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --project)  PROJECT="$2"; shift 2 ;;
    --env)      ENV_FILE="$2"; shift 2 ;;
    --profile)  PROFILE="$2"; shift 2 ;;
    --repo)     REPO="$2"; shift 2 ;;
    --stop)     ACTION="stop"; shift ;;
    --help|-h)  usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage >&2; exit 1 ;;
  esac
done

load_service_env "$PROJECT" SOURCE_REPO SERVICE_NAME SERVICE_PORT CONTAINER_MODULE MAIN_CLASS
REPO="${REPO:-$svc_repo}"

# ---------------------------------------------------------------------------
# Process helpers
# ---------------------------------------------------------------------------
port_listeners() {
  command -v lsof >/dev/null 2>&1 || return 0
  lsof -nP -iTCP:"$1" -sTCP:LISTEN -t 2>/dev/null || true
}

describe_pids() {
  local list
  list=$(printf '%s' "$1" | tr '\n' ',' | sed 's/,$//')
  [[ -z "$list" ]] && return 0
  ps -o pid,lstart,command -p "$list" 2>/dev/null | cut -c1-110 || true
}

# The launch is a three-process chain: this script -> Maven -> the forked
# application JVM that actually holds the port. Killing only the JVM leaves
# Maven (and the script) behind; killing only the script orphans the JVM. So
# walk up from the port holder and collect every process that belongs to it.
collect_launch_pids() {
  local pid="$1" depth=0 parent cmd
  echo "$pid"
  while (( depth < 4 )); do
    parent=$(ps -o ppid= -p "$pid" 2>/dev/null | tr -d ' ')
    [[ -z "$parent" || "$parent" == "0" || "$parent" == "1" ]] && break
    cmd=$(ps -o command= -p "$parent" 2>/dev/null || true)
    [[ "$cmd" == *spring-boot:run* || "$cmd" == *"$(basename "$0")"* ]] || break
    echo "$parent"
    pid="$parent"
    depth=$((depth + 1))
  done
}

is_service_process() {
  local cmd
  cmd=$(ps -o command= -p "$1" 2>/dev/null || true)
  [[ "$cmd" == *"$svc_main_class"* || "$cmd" == *"$REPO"* ]]
}

# Resolve the HTTP port the same way the run path does: an explicit SERVER_PORT
# in the environment wins, then one set by the env file, then service.env's port.
resolve_port() {
  local p="${SERVER_PORT:-}"
  if [[ -z "$p" && -f "$ENV_FILE" ]]; then
    p=$(sed -nE 's/^[[:space:]]*(export[[:space:]]+)?SERVER_PORT=["'"'"']?([0-9]+).*/\2/p' "$ENV_FILE" | head -1)
  fi
  echo "${p:-$svc_port}"
}

wait_for_free_port() {
  local port="$1" limit="$2" waited=0
  while (( waited < limit )); do
    [[ -z "$(port_listeners "$port")" ]] && return 0
    sleep 1
    waited=$((waited + 1))
  done
  [[ -z "$(port_listeners "$port")" ]]
}

stop_service() {
  local port="$1" listeners pid all_pids="" pids

  if ! command -v lsof >/dev/null 2>&1; then
    echo "error: lsof not found — cannot locate the running service" >&2
    return 1
  fi

  listeners=$(port_listeners "$port")
  if [[ -z "$listeners" ]]; then
    echo "Nothing is listening on port $port — the service is not running."
    return 0
  fi

  # Refuse to kill an unrelated process that happens to hold the port.
  for pid in $listeners; do
    if ! is_service_process "$pid"; then
      echo "error: PID $pid holds port $port but is not the $svc_name service — refusing to kill it." >&2
      describe_pids "$pid" >&2
      return 1
    fi
    all_pids+="$(collect_launch_pids "$pid")"$'\n'
  done
  pids=$(printf '%s' "$all_pids" | awk 'NF && !seen[$0]++')

  echo "Stopping the $svc_name service on port $port:"
  describe_pids "$pids"

  # shellcheck disable=SC2086 # deliberate word splitting: one kill for the whole chain
  kill $pids 2>/dev/null || true

  if ! wait_for_free_port "$port" 20; then
    echo "warning: port $port still bound after 20s — sending SIGKILL" >&2
    # shellcheck disable=SC2086
    kill -9 $pids 2>/dev/null || true
    if ! wait_for_free_port "$port" 5; then
      echo "error: port $port is still in use after SIGKILL." >&2
      describe_pids "$(port_listeners "$port")" >&2
      return 1
    fi
  fi

  echo "Stopped — port $port is free."
}

if [[ "$ACTION" == "stop" ]]; then
  if stop_service "$(resolve_port)"; then exit 0; else exit 1; fi
fi

# ---------------------------------------------------------------------------
# Validate
# ---------------------------------------------------------------------------
if [[ ! -f "$ENV_FILE" ]]; then
  echo "error: env file not found: $ENV_FILE" >&2
  exit 1
fi

if [[ ! -d "$REPO" ]]; then
  echo "error: source repo not found: $REPO" >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# Resolve the pinned JDK (MS_KIT_JDK)
# ---------------------------------------------------------------------------
if JAVA_HOME_PINNED=$(/usr/libexec/java_home -v "$MS_KIT_JDK" 2>/dev/null); then
  export JAVA_HOME="$JAVA_HOME_PINNED"
  echo "Using JDK $MS_KIT_JDK: $JAVA_HOME"
else
  echo "warning: JDK $MS_KIT_JDK not found via /usr/libexec/java_home — using system default" >&2
  echo "warning: Lombok may fail if running on a newer JDK" >&2
fi

# ---------------------------------------------------------------------------
# Load env file
# ---------------------------------------------------------------------------
echo "Loading env file: $ENV_FILE"
while IFS= read -r line || [[ -n "$line" ]]; do
  # Skip comments and blank/whitespace-only lines
  [[ "$line" =~ ^[[:space:]]*# ]] && continue
  [[ "$line" =~ ^[[:space:]]*$ ]] && continue
  # Skip lines whose key contains characters invalid for bash identifiers (e.g. hyphens)
  key="${line%%=*}"
  if [[ ! "$key" =~ ^[a-zA-Z_][a-zA-Z0-9_]*$ ]]; then
    echo "warning: skipping invalid identifier: $key" >&2
    continue
  fi
  export "$line"
done < "$ENV_FILE"

# ---------------------------------------------------------------------------
# Port pre-check
# ---------------------------------------------------------------------------
# Runs after the env file is loaded so an env-supplied SERVER_PORT is honoured
# (Spring relaxed binding maps it onto server.port, overriding application.yml).
PORT="${SERVER_PORT:-$svc_port}"

if command -v lsof >/dev/null 2>&1; then
  port_pids=$(port_listeners "$PORT")
  if [[ -n "$port_pids" ]]; then
    echo "error: port $PORT is already in use — the service is likely already running." >&2
    describe_pids "$port_pids" >&2
    echo "hint: run '$(basename "$0") --stop', or set SERVER_PORT to a free port." >&2
    exit 1
  fi
else
  echo "warning: lsof not found — skipping the port $PORT availability check" >&2
fi

# ---------------------------------------------------------------------------
# Build (install all modules so sibling jars are in local repo)
# ---------------------------------------------------------------------------
echo "Building all modules (profile: $PROFILE)..."
echo "---"
cd "$REPO"
mvn clean install -DskipTests -P "$PROFILE"

# ---------------------------------------------------------------------------
# Run
# ---------------------------------------------------------------------------
# spring-boot-devtools runs the application on the "restartedMain" thread, so
# Maven's main thread returns normally and reports BUILD SUCCESS even when the
# Spring context fails to refresh. Maven's exit code alone is therefore not a
# reliable signal — the run output is scanned for Spring's failure banner too.
echo "---"
echo "Starting the $svc_name service (profiles: $PROFILE,local)..."
echo "---"

RUN_LOG="$(mktemp -t run-local)"
trap 'rm -f "$RUN_LOG"' EXIT

set +e
mvn spring-boot:run \
  -pl "$svc_container_module" \
  -P "$PROFILE" \
  -Dspring-boot.run.profiles="$PROFILE,local" 2>&1 | tee "$RUN_LOG"
mvn_status=${PIPESTATUS[0]}
set -e

if [[ $mvn_status -ne 0 ]]; then
  echo "error: maven exited with status $mvn_status" >&2
  exit "$mvn_status"
fi

if grep -qE 'APPLICATION FAILED TO START|Error starting ApplicationContext|Application run failed' "$RUN_LOG"; then
  # Spring's FailureAnalyzer banner ("Description:") is the friendliest reason, but it is
  # only emitted for analysed failures — fall back to the first root cause otherwise.
  reason=$(awk '/^Description:/ {while ((getline line) > 0) if (line !~ /^[[:space:]]*$/) { print line; exit }}' "$RUN_LOG")
  [[ -z "$reason" ]] && reason=$(grep -m1 '^Caused by:' "$RUN_LOG" | cut -c1-160)
  echo "error: the application failed to start (maven still reported success)." >&2
  [[ -n "$reason" ]] && echo "reason: $reason" >&2
  exit 1
fi
