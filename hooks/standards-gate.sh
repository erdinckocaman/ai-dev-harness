#!/usr/bin/env bash
# standards-gate.sh -- the standards gate (AGENTS.md invariant 2, kit/WORKFLOW.md
# invariant 1, docs/adr/0003).
#
# The gate blocks an edit to a file in a registered source repository until the
# session has read every guideline file that the edited path routes to.
#
#   Guarded paths  SOURCE_REPO of every projects/*/service.env in this harness,
#                  read by the one service.env parser, kit/scripts/lib/service-env.sh
#                  (~/ is $HOME, a relative value is relative to its project
#                  folder, the last line wins). The harness root is found from
#                  the location of this script, never from the working directory.
#   Routes         standards/gate-routes.txt, as data (format: the header of
#                  that file). Every matching row applies. This script holds no
#                  route list: a new route is a new row in that file.
#
# Wired as two hooks in .claude/settings.json:
#
#   pre   PreToolUse  (Write|Edit|MultiEdit|NotebookEdit). Exit 2 blocks the
#         edit and the message on stderr names each unread guideline with the
#         reason from its route row.
#   post  PostToolUse (Read|Bash|Grep|Glob). Records each guideline path that
#         the tool call names. Always exits 0.
#
# The read set is a file per session id under $TMPDIR, so a new session starts
# with no reads. There is no bypass: no environment variable, no warn-only mode.
#
# What counts as a read: a path in the tool INPUT (the file a Read opened, the
# command a Bash call ran, the path a Grep searched) that resolves to a guideline
# under this harness's standards/. A relative path resolves against the cwd of
# the payload, or against the hook's own working directory when the payload has
# none. The tool RESPONSE is never searched: GUIDELINES.md names every guideline,
# so its text must not unlock the files it routes to.
#
# Fail closed:
#   - The payload has no target path that the gate can read (it is not JSON, or
#     the field has an unknown name), but its raw text names a registered
#     repository: only the base set ('*' rows) is required.
#   - The route file is missing: a guarded edit is blocked.
#   - The gate itself fails in pre mode: the edit is blocked.
#   - kit/scripts/lib/service-env.sh is missing or broken: the gate cannot read
#     SOURCE_REPO. It blocks an edit whose payload names /<folder>/, where
#     <folder> is the last folder of any SOURCE_REPO line as written, and lets
#     every other edit pass, so an edit outside every repository still works.
#
# Known limits, by design:
#   - Bash is not intercepted. A `sed -i`, a `>` redirect or a heredoc into a
#     source repository passes. No path-certain rule can tell from a command
#     string whether it writes under a path (docs/adr/0003).
#   - A path that is only named counts as read: `grep x standards/GUIDELINES.md`
#     records GUIDELINES.md. A glob such as `cat standards/guidelines/*.md` is
#     expanded when the post hook runs, and records each guideline it matches.
#   - The gate fires only in agent sessions that load this harness's
#     .claude/settings.json. A session started inside a source repository is
#     guarded by the AGENTS.md invariant alone.
#   - A project is registered only under projects/ of this harness;
#     MS_KIT_PROJECTS_DIR is not read, so it cannot hide a repository.
#   - A harness root whose path holds whitespace is not supported.

set -uo pipefail

MODE="${1:-}"
HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HOOK_DIR/.." && pwd)"
ROOT_PHYSICAL="$(cd "$ROOT" && pwd -P)"
STANDARDS="$ROOT/standards"
ROUTES="$STANDARDS/gate-routes.txt"
PROJECTS="$ROOT/projects"
READS_DIR="${TMPDIR:-/tmp}/ai-dev-harness-standards-gate"
TAB="$(printf '\t')"

SERVICE_ENV_LIB="$ROOT/kit/scripts/lib/service-env.sh"
service_env_lib=""
# shellcheck source=../kit/scripts/lib/service-env.sh
if [ -f "$SERVICE_ENV_LIB" ] && source "$SERVICE_ENV_LIB" > /dev/null 2>&1 \
  && declare -F service_env_get > /dev/null; then
  service_env_lib=1
fi

PYTHON=/usr/bin/python3
[ -x "$PYTHON" ] || PYTHON="$(command -v python3 2>/dev/null || echo python3)"

# Reads the hook payload (JSON on stdin) without jq. Prints the session id, then:
#   pre   the target path of the edit (normalized), then its real path
#   post  the cwd, then every string in the payload except the tool response
# Exits non-zero when the payload is not a JSON object.
PARSER="$(cat <<'PY'
import json, os, sys

mode = sys.argv[1]
try:
    data = json.loads(sys.stdin.read())
except Exception:
    sys.exit(3)
if not isinstance(data, dict):
    sys.exit(3)

# Claude Code sends tool_input as an object; Copilot CLI sends toolArgs as a JSON string.
tool_input = data.get("tool_input")
if not isinstance(tool_input, dict):
    args = data.get("toolArgs")
    if isinstance(args, str):
        try:
            args = json.loads(args)
        except Exception:
            args = None
    tool_input = args if isinstance(args, dict) else {}

def field(name):
    for source in (data, tool_input):
        value = source.get(name)
        if isinstance(value, str) and value:
            return value.replace("\n", " ")
    return ""

out = [field("session_id")]
cwd = field("cwd")

if mode == "pre":
    target = field("file_path") or field("notebook_path") or field("path")
    if target.startswith("~/"):
        target = os.path.expanduser(target)
    if target and not os.path.isabs(target):
        target = os.path.join(cwd, target) if os.path.isabs(cwd) else ""
    if target:
        out += [os.path.normpath(target), os.path.realpath(target)]
else:
    out.append(cwd)
    skipped = {"tool_response", "toolResult", "tool_result", "tool_output"}

    def strings(value):
        if isinstance(value, str):
            yield value
        elif isinstance(value, dict):
            for key, item in value.items():
                if key not in skipped:
                    yield from strings(item)
        elif isinstance(value, list):
            for item in value:
                yield from strings(item)

    out += list(strings(data))

sys.stdout.write("\n".join(out) + "\n")
PY
)"

payload="$(cat)"

parse_payload() {
  printf '%s' "$payload" | "$PYTHON" -c "$PARSER" "$1" 2>/dev/null
}

# The read set of a session. The id is sanitized: it becomes a file name.
reads_file_for() {
  local id
  id="$(printf '%s' "$1" | tr -c 'A-Za-z0-9._-' '_')"
  [ -n "$id" ] || id="unknown"
  printf '%s/%s.reads' "$READS_DIR" "$id"
}

# One line per registered repository form: <project><TAB><path>. Both the path
# as written (normalized) and its physical form are listed, so an edit through a
# symlink and an edit to the real path both match.
registered_repos() {
  local env dir name repo logical physical
  for env in "$PROJECTS"/*/service.env; do
    [ -f "$env" ] || continue
    dir="${env%/service.env}"
    name="${dir##*/}"
    repo="$(service_env_get "$env" SOURCE_REPO)"
    [ -n "$repo" ] || continue
    if [ -d "$repo" ]; then
      logical="$(cd "$repo" && pwd)"
      physical="$(cd "$repo" && pwd -P)"
      printf '%s\t%s\n%s\t%s\n' "$name" "$logical" "$name" "$physical"
    else
      printf '%s\t%s\n' "$name" "$repo"
    fi
  done
}

# Route rows that apply: <guideline><TAB><reason>, once per guideline, in file
# order. `routes <path>` gives the rows whose pattern matches the path;
# `routes --base` gives the '*' rows only.
routes() {
  local target="$1" pattern guideline reason
  awk -F'|' '
    /^[[:space:]]*(#|$)/ { next }
    NF < 3 { next }
    { for (i = 1; i <= 3; i++) gsub(/^[[:space:]]+|[[:space:]]+$/, "", $i); print $1 "\t" $2 "\t" $3 }
  ' "$ROUTES" | while IFS="$TAB" read -r pattern guideline reason; do
    [ -n "$guideline" ] || continue
    if [ "$target" = "--base" ]; then
      [ "$pattern" = "*" ] || continue
      printf '%s\t%s\n' "$guideline" "$reason"
    else
      # Unquoted on purpose: the pattern is a glob.
      case "$target" in
        $pattern) printf '%s\t%s\n' "$guideline" "$reason" ;;
      esac
    fi
  done | awk -F'\t' '!seen[$1]++'
}

# Prints the guideline (GUIDELINES.md or guidelines/<name>.md) that an absolute
# path names under this harness's standards/, or nothing.
guideline_of() {
  local path="$1" dir rel candidate
  dir="${path%/*}"
  candidate="$path"
  if [ -d "$dir" ]; then
    candidate="$(cd "$dir" && pwd -P)/${path##*/}"
  fi
  for candidate in "$candidate" "$path"; do
    rel=""
    case "$candidate" in
      "$ROOT_PHYSICAL/standards/"*) rel="${candidate#"$ROOT_PHYSICAL/standards/"}" ;;
      "$ROOT/standards/"*) rel="${candidate#"$ROOT/standards/"}" ;;
    esac
    case "$rel" in
      GUIDELINES.md|guidelines/*.md)
        printf '%s\n' "$rel"
        return
        ;;
    esac
  done
}

# Prints the guideline of every file that a glob path matches; nothing for a
# glob that matches no guideline of this harness.
guidelines_of_glob() {
  local IFS=$'\n' match
  # Unquoted on purpose: the path is a glob.
  for match in $1; do
    [ -f "$match" ] && guideline_of "$match"
  done
  return 0
}

post_main() {
  local parsed session cwd text token path found=""
  parsed="$(parse_payload post)" || return 0
  session="$(printf '%s\n' "$parsed" | sed -n 1p)"
  cwd="$(printf '%s\n' "$parsed" | sed -n 2p)"
  case "$cwd" in
    /*) ;;
    *) cwd="$(pwd)" ;;
  esac
  text="$(printf '%s\n' "$parsed" | sed 1,2d)"

  while IFS= read -r token; do
    [ -n "$token" ] || continue
    case "$token" in
      "~/"*) path="$HOME/${token#"~/"}" ;;
      /*) path="$token" ;;
      *) path="$cwd/$token" ;;
    esac
    token="$(guideline_of "$path")"
    [ -n "$token" ] && found="${found}${token}"$'\n'
  done <<EOF
$(printf '%s\n' "$text" | grep -oE '[A-Za-z0-9._/~-]*(GUIDELINES\.md|guidelines/[A-Za-z0-9._/-]+\.md)' || true)
EOF

  # A glob (cat standards/guidelines/*.md) counts as a read of each guideline it
  # matches under this harness's standards/.
  while IFS= read -r token; do
    token="$(printf '%s' "$token" | tr -d "'\"")"
    case "$token" in
      *standards*|*guidelines*|*GUIDELINES*) ;;
      *) continue ;;
    esac
    case "$token" in
      "~/"*) path="$HOME/${token#"~/"}" ;;
      /*) path="$token" ;;
      *) path="$cwd/$token" ;;
    esac
    token="$(guidelines_of_glob "$path")"
    [ -n "$token" ] && found="${found}${token}"$'\n'
  done <<EOF
$(printf '%s\n' "$text" | grep -oE "[^[:space:];|&<>()\`]*[*?[][^[:space:];|&<>()\`]*" || true)
EOF

  [ -n "$found" ] || return 0
  mkdir -p "$READS_DIR"
  printf '%s' "$found" | sort -u >> "$(reads_file_for "$session")"
}

# Without the service.env library: block an edit whose payload names the last
# folder of any SOURCE_REPO line as written. Deliberately cruder than the parser:
# it can only block more, never less, than the parser would.
pre_without_lib() {
  local env value folder
  for env in "$PROJECTS"/*/service.env; do
    [ -f "$env" ] || continue
    while IFS= read -r value; do
      value="$(printf '%s' "${value#*=}" | tr -d '[:space:]')"
      while [ "${value%/}" != "$value" ]; do value="${value%/}"; done
      folder="${value##*/}"
      case "$folder" in ''|'~'|.|..) continue ;; esac
      if printf '%s' "$payload" | grep -qF -- "/$folder/"; then
        {
          echo "BLOCKED by the standards gate: it cannot read service.env, because"
          echo "  $SERVICE_ENV_LIB"
          echo "is missing or broken. This edit names the folder '$folder' of a SOURCE_REPO in"
          echo "  $env"
          echo "Restore kit/scripts/lib/service-env.sh."
        } >&2
        return 2
      fi
    done <<EOF
$(grep 'SOURCE_REPO' "$env" | grep '=')
EOF
  done
  return 0
}

pre_main() {
  local parsed session target candidate project="" form name repo required missing="" \
    reads_file guideline reason unparsed=""
  if [ -z "$service_env_lib" ]; then
    pre_without_lib
    return
  fi
  parsed="$(parse_payload pre)" || parsed=""
  session="$(printf '%s\n' "$parsed" | sed -n 1p)"

  # Find the registered repository that holds the target.
  while IFS= read -r candidate; do
    [ -n "$candidate" ] || continue
    while IFS="$TAB" read -r name repo; do
      [ -n "$repo" ] || continue
      case "$candidate" in
        "$repo"/*) project="$name"; target="$candidate"; break 2 ;;
      esac
    done <<EOF
$(registered_repos)
EOF
  done <<EOF
$(printf '%s\n' "$parsed" | sed 1d)
EOF

  if [ -z "$project" ]; then
    # A target path that lies outside every repository is not the gate's business.
    [ -z "$(printf '%s\n' "$parsed" | sed -n 2p)" ] || return 0
    # No target path could be read: fail closed if the raw payload names a repository.
    while IFS="$TAB" read -r name repo; do
      [ -n "$repo" ] || continue
      if printf '%s' "$payload" | grep -qF -- "$repo/"; then
        project="$name"
        target="(unparsed hook payload that names $repo/)"
        unparsed=1
        break
      fi
    done <<EOF
$(registered_repos)
EOF
    [ -n "$project" ] || return 0
  fi

  if [ ! -f "$ROUTES" ]; then
    {
      echo "BLOCKED by the standards gate: the route file is missing."
      echo "  $ROUTES"
      echo "The gate cannot tell which guidelines this edit needs, so it blocks every edit in"
      echo "a registered source repository. Restore standards/gate-routes.txt."
    } >&2
    return 2
  fi

  if [ -n "$unparsed" ]; then
    required="$(routes --base)"
  else
    required="$(routes "$target")"
  fi

  reads_file="$(reads_file_for "$session")"
  while IFS="$TAB" read -r guideline reason; do
    [ -n "$guideline" ] || continue
    if [ -f "$reads_file" ] && grep -qxF -- "$guideline" "$reads_file"; then
      continue
    fi
    missing="${missing}${guideline}${TAB}${reason}"$'\n'
  done <<EOF
$required
EOF

  [ -n "$missing" ] || return 0

  {
    echo "BLOCKED by the standards gate."
    echo
    echo "You are about to edit a file in the source repository of project '$project':"
    echo "  $target"
    if [ -n "$unparsed" ]; then
      echo "The gate could not read the target path from the hook payload, so only the base"
      echo "set applies."
    fi
    echo
    echo "AGENTS.md invariant 2: read the guideline files that this edit routes to first."
    echo "Still unread in this session:"
    echo
    while IFS="$TAB" read -r guideline reason; do
      [ -n "$guideline" ] || continue
      echo "  $STANDARDS/$guideline"
      echo "      why: $reason"
    done <<EOF
$missing
EOF
    echo
    echo "Read them, then retry the edit. Reading GUIDELINES.md alone is not enough: it is"
    echo "the routing table, and the gate requires the files it routes this path to."
  } >&2
  return 2
}

case "$MODE" in
  post)
    ( post_main ) || true
    exit 0
    ;;
  pre)
    ( pre_main )
    rc=$?
    case "$rc" in
      0|2) exit "$rc" ;;
    esac
    echo "BLOCKED: the standards gate failed (exit $rc), so it blocks the edit." >&2
    exit 2
    ;;
  *)
    echo "usage: standards-gate.sh {pre|post}" >&2
    exit 1
    ;;
esac
