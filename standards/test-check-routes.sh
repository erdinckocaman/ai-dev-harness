#!/usr/bin/env bash
# test-check-routes.sh
#
# Tests standards/check-routes.sh at its outer seam: the exit status and the
# output for a given standards directory. Each case builds a small standards
# directory in a temp folder, runs the check against it, and asserts pass or
# fail plus a fragment of the message. The last case runs the check against the
# real standards/ directory of this repository.
#
# Run: bash standards/test-check-routes.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHECK="$SCRIPT_DIR/check-routes.sh"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/test-check-routes.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

failures=0
cases=0

# A minimal valid standards directory: a routing file that names both guideline
# files, and a route file with a base row and one extension row.
make_valid() {
  local dir="$1"
  mkdir -p "$dir/guidelines"
  printf '# Guide\n\n| When | Read |\n|---|---|\n| Any task | `guidelines/core.md` |\n| Java | `guidelines/java.md` |\n' > "$dir/GUIDELINES.md"
  printf '# Core\n' > "$dir/guidelines/core.md"
  printf '# Java\n' > "$dir/guidelines/java.md"
  cat > "$dir/gate-routes.txt" <<'ROUTES'
# pattern | guideline | reason

*      | GUIDELINES.md       | the routing table
*      | guidelines/core.md  | where every task starts
*.java | guidelines/java.md  | you are editing a .java file
ROUTES
}

# expect <name> <pass|fail> <message fragment or empty> <dir>
expect() {
  local name="$1" want="$2" fragment="$3" dir="$4" out status
  cases=$((cases + 1))
  out="$(bash "$CHECK" "$dir" 2>&1)"
  status=$?
  if [ "$want" = pass ] && [ "$status" -ne 0 ]; then
    echo "FAIL $name: expected pass, got exit $status"; echo "$out" | sed 's/^/    /'
    failures=$((failures + 1)); return
  fi
  if [ "$want" = fail ] && [ "$status" -eq 0 ]; then
    echo "FAIL $name: expected fail, got exit 0"; echo "$out" | sed 's/^/    /'
    failures=$((failures + 1)); return
  fi
  if [ -n "$fragment" ] && ! printf '%s' "$out" | grep -qF -- "$fragment"; then
    echo "FAIL $name: output lacks '$fragment'"; echo "$out" | sed 's/^/    /'
    failures=$((failures + 1)); return
  fi
  echo "ok   $name"
}

case_dir() { local d="$WORK/$1"; make_valid "$d"; echo "$d"; }

d="$(case_dir valid)"
expect "valid directory passes; comments and blank lines are skipped" pass "" "$d"

d="$(case_dir missing-guideline)"
echo '*.sql | guidelines/sql.md | you are editing a .sql file' >> "$d/gate-routes.txt"
expect "row naming a missing guideline fails with file and line" fail "gate-routes.txt:6: guidelines/sql.md does not exist" "$d"

d="$(case_dir two-fields)"
echo '*.sql | guidelines/core.md' >> "$d/gate-routes.txt"
expect "row with two fields fails" fail "gate-routes.txt:6: expected 3 fields" "$d"

d="$(case_dir four-fields)"
echo '*.sql | guidelines/core.md | reason | extra' >> "$d/gate-routes.txt"
expect "row with four fields fails" fail "gate-routes.txt:6: expected 3 fields" "$d"

d="$(case_dir empty-reason)"
echo '*.sql | guidelines/core.md |   ' >> "$d/gate-routes.txt"
expect "row with an empty reason fails" fail "gate-routes.txt:6: empty field" "$d"

d="$(case_dir space-in-pattern)"
echo '*.s ql | guidelines/core.md | reason' >> "$d/gate-routes.txt"
expect "pattern with whitespace fails" fail "gate-routes.txt:6: pattern contains whitespace" "$d"

d="$(case_dir escaping-path)"
echo '*.sql | guidelines/../../etc.md | reason' >> "$d/gate-routes.txt"
expect "guideline path that leaves standards/ fails" fail "gate-routes.txt:6: bad guideline path" "$d"

d="$(case_dir no-base)"
sed -i.bak '/^\*  /d' "$d/gate-routes.txt"
expect "route file without a base row for GUIDELINES.md fails" fail "no '*' row names GUIDELINES.md" "$d"

d="$(case_dir no-route-file)"
rm "$d/gate-routes.txt"
expect "missing route file fails" fail "gate-routes.txt not found" "$d"

d="$(case_dir table-names-missing)"
printf '| Kafka | `guidelines/kafka.md` |\n' >> "$d/GUIDELINES.md"
expect "GUIDELINES.md naming a missing file fails" fail "GUIDELINES.md names guidelines/kafka.md, which does not exist" "$d"

d="$(case_dir orphan)"
printf '# Orphan\n' > "$d/guidelines/orphan.md"
expect "guideline file that GUIDELINES.md never names fails" fail "guidelines/orphan.md is not named in GUIDELINES.md" "$d"

expect "the real standards/ directory passes" pass "" "$SCRIPT_DIR"

echo
echo "$((cases - failures))/$cases passed"
[ "$failures" -eq 0 ]
