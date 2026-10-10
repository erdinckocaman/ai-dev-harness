#!/usr/bin/env bash
#
# set-version.sh — bump or set the Maven version across every module of a
# Maven microservice reactor, and the Helm chart's appVersion.
#
# The version (e.g. 1.2.5) is duplicated in every pom.xml: the root <version>
# plus each child module's <parent><version>, and again as appVersion in the
# Helm Chart.yaml. This script rewrites all of them in one shot, keeping them
# consistent. The chart's own `version:` (chart revision) is left untouched.
#
# This script lives in the workspace, not in the code repo.
# It edits the pom.xml files of the external source repository.
#
# Usage:
#   set-version.sh                 Print the current version and usage.
#   set-version.sh <X.Y.Z>         Set the version to an exact value.
#   set-version.sh bump [patch|minor|major]
#                                  Increment a segment (default: patch).
#                                    1.2.5 -> bump        -> 1.2.6
#                                    1.2.5 -> bump minor  -> 1.3.0
#                                    1.2.5 -> bump major  -> 2.0.0
#
# The project (--project <name>, default: the one the working directory is in)
# supplies the repository and the root artifactId through its service.env;
# --repo <path> overrides the repository.
#
# The script edits files only. It does not run git or maven and does not commit,
# tag, or build — committing the change is up to you.
#
# Files touched: every pom.xml (excluding target/) and every Chart.yaml
# (excluding target/), whose `appVersion:` is set to the target version.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/service-env.sh
source "$SCRIPT_DIR/lib/service-env.sh"
# shellcheck source=lib/pom.sh
source "$SCRIPT_DIR/lib/pom.sh"

readonly VERSION_RE='^[0-9]+\.[0-9]+\.[0-9]+$'

die() {
  echo "error: $*" >&2
  exit 1
}

usage() {
  cat <<'EOF'
Usage:
  set-version.sh                 Print the current version and usage.
  set-version.sh <X.Y.Z>         Set the version to an exact value.
  set-version.sh bump [patch|minor|major]
                                 Increment a segment (default: patch).
                                   1.2.5 -> bump        -> 1.2.6
                                   1.2.5 -> bump minor  -> 1.3.0
                                   1.2.5 -> bump major  -> 2.0.0

Options:
  --project <name>  The service project (a folder under MS_KIT_PROJECTS_DIR, with a
                    service.env). Default: the project the working directory is in.
  --repo <path>     The source repository. Default: SOURCE_REPO of service.env.

Edits pom.xml files and the Helm Chart.yaml appVersion only — no git, no maven,
no commit/tag/build.
EOF
}

# --- Parse arguments ---------------------------------------------------------

project=""
repo=""
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
    -h|--help)
      usage
      exit 0
      ;;
    -*)
      die "unknown option: $1"
      ;;
    *)
      positional+=("$1")
      shift
      ;;
  esac
done

# Resolve target repo: flag > service.env.
load_service_env "$project" SOURCE_REPO ROOT_ARTIFACT_ID
repo="${repo:-$svc_repo}"
[ -d "$repo" ] || die "repo directory not found: $repo"
readonly root_pom="$repo/pom.xml"
[ -f "$root_pom" ] || die "root pom.xml not found: $root_pom"

# --- Read the current version from the root pom ------------------------------
# lib/pom.sh: the first <version> after the root <artifactId> line. new-project.sh
# reads it the same way for its fit check.

root_version() {
  pom_root_version "$root_pom" "$svc_root_artifact_id"
}

current="$(root_version)"

[ -n "$current" ] || die "could not determine current version from $root_pom"
[[ "$current" =~ $VERSION_RE ]] || \
  die "current version '$current' is not strict MAJOR.MINOR.PATCH; refusing to guess"

# --- Determine the target version --------------------------------------------

target=""
if [ ${#positional[@]} -eq 0 ]; then
  echo "current version: $current"
  echo
  usage
  exit 0
fi

case "${positional[0]}" in
  bump)
    segment="${positional[1]:-patch}"
    IFS='.' read -r major minor patch <<<"$current"
    case "$segment" in
      major) major=$((major + 1)); minor=0; patch=0 ;;
      minor) minor=$((minor + 1)); patch=0 ;;
      patch) patch=$((patch + 1)) ;;
      *) die "unknown bump segment '$segment' (expected: patch, minor, or major)" ;;
    esac
    [ ${#positional[@]} -le 2 ] || die "too many arguments for 'bump'"
    target="${major}.${minor}.${patch}"
    ;;
  *)
    [ ${#positional[@]} -eq 1 ] || die "too many arguments; expected a single version"
    target="${positional[0]}"
    [[ "$target" =~ $VERSION_RE ]] || \
      die "invalid version '$target'; expected strict MAJOR.MINOR.PATCH (e.g. 1.3.0)"
    ;;
esac

# --- Apply -------------------------------------------------------------------

poms=()
while IFS= read -r pom_path; do
  poms+=("$pom_path")
done < <(find "$repo" -name pom.xml -not -path '*/target/*' | sort)
[ ${#poms[@]} -gt 0 ] || die "no pom.xml files found under $repo"

charts=()
while IFS= read -r chart_path; do
  charts+=("$chart_path")
done < <(find "$repo" -name Chart.yaml -not -path '*/target/*' | sort)

old_tag="<version>${current}</version>"
new_tag="<version>${target}</version>"

changed=()
if [ "$target" != "$current" ]; then
  for pom in "${poms[@]}"; do
    if grep -qF "$old_tag" "$pom"; then
      # Portable in-place edit (GNU/BSD sed): write to temp, then move.
      tmp="$(mktemp)"
      sed "s|${old_tag}|${new_tag}|g" "$pom" >"$tmp"
      mv "$tmp" "$pom"
      changed+=("$pom")
    fi
  done
fi

# The chart's appVersion tracks the application version, so it is rewritten to
# the target regardless of what it held before — it can drift from the poms
# (e.g. a chart edited by hand), and a drifted value must be corrected even when
# the pom version is already the target. The chart's own `version:` (the chart
# revision) is a different number and is left alone.
for chart in "${charts[@]}"; do
  grep -qE '^[[:space:]]*appVersion:' "$chart" || \
    die "no appVersion field in $chart"
  if grep -qE "^[[:space:]]*appVersion:[[:space:]]*\"?${target}\"?[[:space:]]*$" "$chart"; then
    continue
  fi
  tmp="$(mktemp)"
  sed -E "s|^([[:space:]]*)appVersion:.*$|\\1appVersion: \"${target}\"|" "$chart" >"$tmp"
  mv "$tmp" "$chart"
  changed+=("$chart")
done

if [ ${#changed[@]} -eq 0 ]; then
  echo "version already $current — no change"
  exit 0
fi

# --- Self-verify -------------------------------------------------------------

stale=()
if [ "$target" != "$current" ]; then
  for pom in "${poms[@]}"; do
    if grep -qF "$old_tag" "$pom"; then
      stale+=("$pom")
    fi
  done
fi
[ ${#stale[@]} -eq 0 ] || die "stale version '$current' still present in: ${stale[*]}"

# Confirm every chart now reports the target appVersion.
for chart in "${charts[@]}"; do
  grep -qE "^[[:space:]]*appVersion:[[:space:]]*\"?${target}\"?[[:space:]]*$" "$chart" || \
    die "post-edit verification failed: appVersion in $chart is not '$target'"
done

# Confirm the root pom now reports the target version.
root_now="$(root_version)"
[ "$root_now" = "$target" ] || \
  die "post-edit verification failed: root pom reports '$root_now', expected '$target'"

# --- Summary -----------------------------------------------------------------

echo "repo:    $repo"
echo "version: $current -> $target"
echo "updated ${#changed[@]} file(s):"
for path in "${changed[@]}"; do
  echo "  ${path#"$repo"/}"
done
