#!/usr/bin/env bash
#
# Gated runner for the hurl acceptance suite of a microservice project.
#
# It runs the suites of <projects>/<name>/acceptance-tests/: --project <name>, or the
# project the working directory is in. Paths below (suites/, environments/, reports/)
# are relative to that folder.
#
# Some entries cannot run against every target. Those entries carry `[Options] skip: {{someVar}}`
# and their block is annotated with one of two gate kinds:
#
#   # @requires <version> skip=<someVar>        version gate — target must be new enough
#   # @requires-env <precondition> skip=<var>   precondition gate — target must be set up a way
#
# A version gate is resolved from --app-version: blocks needing more than the target runs are
# skipped. Without --app-version nothing is version-skipped — the suite behaves like a plain hurl
# invocation, with a warning on stderr.
#
# A precondition gate is NOT about the version, so --app-version must never satisfy it: the
# target has to be *arranged* a certain way (e.g. its mail transport deliberately unavailable).
# Such a block is skipped unless you declare the precondition with --precondition <name>.
#
# Usage:
#   run-suite.sh                                   # local, every suite, nothing skipped
#   run-suite.sh --project sample-service          # name the project
#   run-suite.sh --env test --app-version 1.2.5    # skip blocks newer than 1.2.5
#   run-suite.sh --env dev -- --report-html reports/html
#   run-suite.sh --suite email                     # any suite name(s), without the .hurl
#   run-suite.sh --precondition mail-transport-unavailable   # run that gated block too
#
# Everything after `--` is forwarded to hurl verbatim.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/service-env.sh
source "$SCRIPT_DIR/lib/service-env.sh"

PROJECT=""
ENV_NAME="local"
APP_VERSION=""
SUITES=()
PRECONDITIONS=()
HURL_EXTRA=()

# The header comment above, up to the first line that is not a comment.
usage() {
  awk 'NR == 1 { next } /^#/ { sub(/^# ?/, ""); print; next } { exit }' "${BASH_SOURCE[0]}"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --project) PROJECT="$2"; shift 2 ;;
    --env) ENV_NAME="$2"; shift 2 ;;
    --app-version) APP_VERSION="$2"; shift 2 ;;
    --precondition) PRECONDITIONS+=("$2"); shift 2 ;;
    --suite) SUITES+=("$2"); shift 2 ;;
    -h|--help) usage; exit 0 ;;
    --) shift; HURL_EXTRA=("$@"); break ;;
    *) echo "run-suite.sh: unknown argument '$1' (use -- to forward flags to hurl)" >&2; exit 2 ;;
  esac
done

load_service_env "$PROJECT"
cd "$project_dir/acceptance-tests" 2>/dev/null \
  || { echo "run-suite.sh: project '$project_name' has no acceptance-tests/ folder" >&2; exit 2; }

if [[ ${#SUITES[@]} -eq 0 ]]; then
  for f in suites/*.hurl; do
    [[ -f "$f" ]] && SUITES+=("$(basename "$f" .hurl)")
  done
  [[ ${#SUITES[@]} -gt 0 ]] || { echo "run-suite.sh: no suites in $PWD/suites/" >&2; exit 2; }
fi

ENV_FILE="environments/${ENV_NAME}.env"
[[ -f "$ENV_FILE" ]] || { echo "run-suite.sh: no such environment file: $ENV_FILE" >&2; exit 2; }

SUITE_FILES=()
for s in "${SUITES[@]}"; do
  f="suites/${s%.hurl}.hurl"
  [[ -f "$f" ]] || { echo "run-suite.sh: no such suite: $f" >&2; exit 2; }
  SUITE_FILES+=("$f")
done

# `sort -V` decides the ordering; equal versions must count as satisfied, so the test is
# "required is NOT strictly greater than actual".
version_satisfied() { # required actual
  [[ "$1" == "$2" ]] && return 0
  [[ "$(printf '%s\n%s\n' "$1" "$2" | sort -V | head -1)" == "$1" ]]
}

GATE_ARGS=()
GATE_VARS=()      # every variable named by an annotation, once
SKIP_VARS=()      # those at least one gate refused
SKIPPED=()        # human-readable reasons, one per refusing gate
MATCHED_CONDS=()  # preconditions that actually matched an annotation

in_list() { # needle list...
  local needle="$1"; shift
  local item
  for item in "$@"; do [[ "$item" == "$needle" ]] && return 0; done
  return 1
}

note_var() { # var — remember it, and demand its default
  in_list "$1" ${GATE_VARS[@]+"${GATE_VARS[@]}"} && return 0
  if grep -q "^${1}=" environments/common.env; then :; else
    echo "run-suite.sh: '${1}' is annotated in a suite but has no default in environments/common.env" >&2
    exit 2
  fi
  GATE_VARS+=("$1")
}

refuse() { # var reason
  in_list "$1" ${SKIP_VARS[@]+"${SKIP_VARS[@]}"} || SKIP_VARS+=("$1")
  # One line per distinct reason: a block repeats its annotation on every entry it covers.
  in_list "${1} — ${2}" ${SKIPPED[@]+"${SKIPPED[@]}"} || SKIPPED+=("${1} — ${2}")
}

# Version gates: satisfied by a new-enough target.
while read -r required var; do
  [[ -z "${var:-}" ]] && continue
  note_var "$var"
  if [[ -n "$APP_VERSION" ]] && ! version_satisfied "$required" "$APP_VERSION"; then
    refuse "$var" "needs app version ${required}, target runs ${APP_VERSION}"
  fi
done < <(grep -ho '^# @requires [^ ]* skip=[^ ]*' "${SUITE_FILES[@]}" \
           | sed 's/^# @requires //; s/skip=//')

# Precondition gates: satisfied by how the target is *arranged*, never by its version. Passing
# --app-version must not enable one of these blocks, so they run only when the arrangement is
# declared with --precondition.
while read -r cond var; do
  [[ -z "${var:-}" ]] && continue
  note_var "$var"
  if in_list "$cond" ${PRECONDITIONS[@]+"${PRECONDITIONS[@]}"}; then
    in_list "$cond" ${MATCHED_CONDS[@]+"${MATCHED_CONDS[@]}"} || MATCHED_CONDS+=("$cond")
  else
    refuse "$var" "needs the target arranged '${cond}' (pass --precondition ${cond})"
  fi
done < <(grep -ho '^# @requires-env [^ ]* skip=[^ ]*' "${SUITE_FILES[@]}" \
           | sed 's/^# @requires-env //; s/skip=//')

# A --precondition matching no annotation is a typo that fails silently: the block it was meant
# to enable stays skipped and the run still reports green.
for cond in ${PRECONDITIONS[@]+"${PRECONDITIONS[@]}"}; do
  in_list "$cond" ${MATCHED_CONDS[@]+"${MATCHED_CONDS[@]}"} || {
    echo "run-suite.sh: --precondition '${cond}' matches no @requires-env annotation in the selected suite(s)" >&2
    exit 2
  }
done

# One decision per variable — a block gated twice runs only if every one of its gates is met.
RAN_COUNT=0
for var in ${GATE_VARS[@]+"${GATE_VARS[@]}"}; do
  if in_list "$var" ${SKIP_VARS[@]+"${SKIP_VARS[@]}"}; then
    GATE_ARGS+=(--variable "${var}=true")
  else
    GATE_ARGS+=(--variable "${var}=false")
    RAN_COUNT=$((RAN_COUNT + 1))
  fi
done

if [[ -z "$APP_VERSION" ]]; then
  echo "run-suite.sh: no --app-version given — no version gate skips anything." >&2
fi
echo "run-suite.sh: ${#SKIP_VARS[@]} gated block(s) skipped, ${RAN_COUNT} gated block(s) run." >&2
for b in ${SKIPPED[@]+"${SKIPPED[@]}"}; do echo "  skipped: $b" >&2; done

set -x
exec hurl --test --jobs 1 \
  --variables-file environments/common.env \
  --variables-file "$ENV_FILE" \
  ${GATE_ARGS[@]+"${GATE_ARGS[@]}"} \
  ${HURL_EXTRA[@]+"${HURL_EXTRA[@]}"} \
  "${SUITE_FILES[@]}"
