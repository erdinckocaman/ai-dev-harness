#!/usr/bin/env bash
# check-routes.sh
#
# Checks that the standards directory is consistent:
#   - gate-routes.txt is well formed (format: see the header of that file),
#   - every guideline that a route row names exists,
#   - a '*' row names GUIDELINES.md (the gate's base set starts there),
#   - every guidelines/*.md path that GUIDELINES.md names exists,
#   - every file under guidelines/ is named in GUIDELINES.md.
#
# Usage: bash standards/check-routes.sh [standards-dir]
# The default directory is the one that holds this script.
# Exit 0 when all checks pass, 1 otherwise. Each problem is one line on stdout,
# as <file>:<line>: <message> where a line number applies.
# Runs on the macOS bash 3.2 and the BSD tools.

set -uo pipefail

DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
ROUTES="$DIR/gate-routes.txt"
GUIDE="$DIR/GUIDELINES.md"
errors=0

problem() { echo "$1"; errors=$((errors + 1)); }

trim() {
  local s="$1"
  s="${s#"${s%%[![:space:]]*}"}"
  s="${s%"${s##*[![:space:]]}"}"
  printf '%s' "$s"
}

if [ ! -f "$ROUTES" ]; then
  problem "gate-routes.txt not found in $DIR"
else
  base_has_guide=0
  n=0
  rows=0
  while IFS= read -r line || [ -n "$line" ]; do
    n=$((n + 1))
    stripped="$(trim "$line")"
    case "$stripped" in ''|'#'*) continue ;; esac
    rows=$((rows + 1))
    where="gate-routes.txt:$n"

    bars="${stripped//[^|]/}"
    if [ "${#bars}" -ne 2 ]; then
      problem "$where: expected 3 fields separated by '|', got $(( ${#bars} + 1 ))"
      continue
    fi
    IFS='|' read -r pattern guideline reason <<< "$stripped"
    pattern="$(trim "$pattern")"
    guideline="$(trim "$guideline")"
    reason="$(trim "$reason")"
    if [ -z "$pattern" ] || [ -z "$guideline" ] || [ -z "$reason" ]; then
      problem "$where: empty field"
      continue
    fi
    case "$pattern" in
      *[[:space:]]*) problem "$where: pattern contains whitespace"; continue ;;
    esac
    if ! printf '%s' "$guideline" | grep -qE '^(GUIDELINES\.md|guidelines/[A-Za-z0-9_-]+(/[A-Za-z0-9_-]+)*\.md)$'; then
      problem "$where: bad guideline path '$guideline' (want GUIDELINES.md or guidelines/<name>.md)"
      continue
    fi
    if [ ! -f "$DIR/$guideline" ]; then
      problem "$where: $guideline does not exist"
    fi
    if [ "$pattern" = '*' ] && [ "$guideline" = GUIDELINES.md ]; then
      base_has_guide=1
    fi
  done < "$ROUTES"

  [ "$rows" -gt 0 ] || problem "gate-routes.txt: no route rows"
  [ "$base_has_guide" -eq 1 ] || problem "gate-routes.txt: no '*' row names GUIDELINES.md"
fi

if [ ! -f "$GUIDE" ]; then
  problem "GUIDELINES.md not found in $DIR"
else
  named="$(grep -oE 'guidelines/[A-Za-z0-9_/-]+\.md' "$GUIDE" | sort -u)"
  for path in $named; do
    [ -f "$DIR/$path" ] || problem "GUIDELINES.md names $path, which does not exist"
  done
  if [ -d "$DIR/guidelines" ]; then
    for path in $(cd "$DIR" && find guidelines -type f -name '*.md' | sort); do
      printf '%s\n' "$named" | grep -qxF "$path" || problem "$path is not named in GUIDELINES.md"
    done
  fi
fi

if [ "$errors" -gt 0 ]; then
  echo "check-routes: $errors problem(s)"
  exit 1
fi
echo "check-routes: OK"
