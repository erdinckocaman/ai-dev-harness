#!/usr/bin/env bash
# test-standards-gate.sh -- tests for hooks/standards-gate.sh.
#
# Builds a throwaway harness in a temp directory: a copy of the gate, a copy of
# standards/, and projects/*/service.env files that register temp source
# repositories. Then it feeds the gate hook payloads, the same JSON the agent
# tool sends, and checks the exit status and the block message. Read sets go to
# a temp TMPDIR, so the developer's own sessions are never touched.
#
# Usage: bash hooks/test-standards-gate.sh     (runs on the macOS /bin/bash 3.2)

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REAL_ROOT="$(cd "$HERE/.." && pwd)"

SANDBOX="$(mktemp -d)"
trap 'rm -rf "$SANDBOX"' EXIT
export TMPDIR="$SANDBOX/tmp"
mkdir -p "$TMPDIR"
export HOME="$SANDBOX/home"
mkdir -p "$HOME"

# make_harness <dir>: a harness copy with the gate, the standards and the service.env
# library, no projects/.
make_harness() {
  mkdir -p "$1/hooks" "$1/kit/scripts/lib"
  cp "$REAL_ROOT/hooks/standards-gate.sh" "$1/hooks/"
  cp -R "$REAL_ROOT/standards" "$1/standards"
  cp "$REAL_ROOT/kit/scripts/lib/service-env.sh" "$1/kit/scripts/lib/"
}

H="$SANDBOX/harness"
make_harness "$H"
ALPHA="$SANDBOX/src/alpha-service"       # registered by an absolute path
BETA="$HOME/code/beta-service"           # registered by a ~/ path
GAMMA="$SANDBOX/src/gamma-service"       # registered by a path relative to its project folder
DELTA="$SANDBOX/src/delta-service"       # registered by a spaced line, after an older value
DELTA_OLD="$SANDBOX/src/delta-old"
OUTSIDE="$SANDBOX/src/unregistered-service"
mkdir -p "$ALPHA" "$BETA" "$GAMMA" "$DELTA" "$DELTA_OLD" "$OUTSIDE" "$H/projects/alpha" \
  "$H/projects/beta" "$H/projects/gamma" "$H/projects/delta" "$H/projects/no-repo" "$H/projects/no-env"
printf '# alpha\nSOURCE_REPO=%s\nSERVICE_NAME=alpha\n' "$ALPHA" > "$H/projects/alpha/service.env"
printf 'SOURCE_REPO=~/code/beta-service/\n' > "$H/projects/beta/service.env"
printf 'SOURCE_REPO=../../../src/gamma-service\n' > "$H/projects/gamma/service.env"
printf 'SOURCE_REPO=%s\n  SOURCE_REPO =  %s  \r\n' "$DELTA_OLD" "$DELTA" > "$H/projects/delta/service.env"
printf '# no source repository yet\nSERVICE_NAME=draft\nNOT_A_KEY_LINE\n' > "$H/projects/no-repo/service.env"

GATE="$H/hooks/standards-gate.sh"

pass=0
fail=0

report() {
  if [ "$1" = "ok" ]; then
    pass=$((pass + 1))
    printf 'ok   %s\n' "$2"
  else
    fail=$((fail + 1))
    printf 'FAIL %s\n     %s\n' "$2" "$3"
  fi
}

# Runs the gate. Sets last_code and last_stderr (globals: a $(...) subshell
# would lose the stderr capture).
# The gate runs from GATE_PWD, the working directory of the agent session.
GATE_PWD="$SANDBOX"
last_code=0
last_stderr=""
run_gate() {
  local gate="$1" mode="$2" payload="$3" err="$SANDBOX/stderr.out"
  last_code=0
  (cd "$GATE_PWD" && printf '%s' "$payload" | /bin/bash "$gate" "$mode" 2>"$err" >/dev/null) || last_code=$?
  last_stderr="$(cat "$err")"
}

run_pre() { run_gate "$GATE" pre "$1"; }

edit_payload() {
  local session="$1" field="$2" path="$3"
  printf '{"session_id":"%s","hook_event_name":"PreToolUse","tool_name":"Edit","tool_input":{"%s":"%s","old_string":"a","new_string":"b"}}' \
    "$session" "$field" "$path"
}

# A Read of a guideline by its absolute path, as the agent tool reports it.
record_read() {
  local session="$1" guideline="$2"
  run_gate "$GATE" post "$(printf '{"session_id":"%s","cwd":"%s","hook_event_name":"PostToolUse","tool_name":"Read","tool_input":{"file_path":"%s/standards/%s"},"tool_response":{"type":"text"}}' \
    "$session" "$H" "$H" "$guideline")"
}

# A Bash command, with an optional cwd (empty: no cwd field).
record_bash() {
  local session="$1" cwd="$2" command="$3" cwd_field=""
  [ -z "$cwd" ] || cwd_field="$(printf '"cwd":"%s",' "$cwd")"
  run_gate "$GATE" post "$(printf '{"session_id":"%s",%s"hook_event_name":"PostToolUse","tool_name":"Bash","tool_input":{"command":"%s"},"tool_response":{"stdout":""}}' \
    "$session" "$cwd_field" "$command")"
}

record_base() {
  record_read "$1" GUIDELINES.md
  record_read "$1" guidelines/core-principles.md
}

assert_blocked() {
  if [ "$last_code" = "2" ]; then report ok "$1"; else report fail "$1" "expected exit 2, got $last_code (stderr: $last_stderr)"; fi
}

assert_allowed() {
  if [ "$last_code" = "0" ]; then report ok "$1"; else report fail "$1" "expected exit 0, got $last_code (stderr: $last_stderr)"; fi
}

assert_mentions() {
  if printf '%s' "$last_stderr" | grep -qF -- "$2"; then report ok "$1"; else report fail "$1" "block message does not name '$2'"; fi
}

assert_not_mentions() {
  if printf '%s' "$last_stderr" | grep -qF -- "$2"; then report fail "$1" "block message names '$2'"; else report ok "$1"; fi
}

ALL_GUIDELINES="GUIDELINES.md guidelines/core-principles.md guidelines/java-coding-conventions.md
guidelines/project-structure.md guidelines/testing-strategy.md guidelines/unit-testing.md
guidelines/integration-testing.md guidelines/database-and-flyway.md"

# check_kind <label> <session> <path> <required guidelines, space separated>
# A cold edit is blocked and names exactly the required set; reading all but
# the last one still blocks; reading the last one allows the edit.
check_kind() {
  local label="$1" session="$2" path="$3" required="$4" g last=""
  run_pre "$(edit_payload "$session" file_path "$path")"
  assert_blocked "$label: cold edit is blocked"
  for g in $ALL_GUIDELINES; do
    case " $required " in
      *" $g "*) assert_mentions "$label: names $g" "$H/standards/$g" ;;
      *) assert_not_mentions "$label: does not demand $g" "$H/standards/$g" ;;
    esac
  done
  for g in $required; do last="$g"; done
  for g in $required; do
    [ "$g" = "$last" ] || record_read "$session" "$g"
  done
  run_pre "$(edit_payload "$session" file_path "$path")"
  assert_blocked "$label: still blocked while $last is unread"
  assert_mentions "$label: names the last unread guideline" "$H/standards/$last"
  record_read "$session" "$last"
  run_pre "$(edit_payload "$session" file_path "$path")"
  assert_allowed "$label: allowed once the routed set is read"
}

BASE="GUIDELINES.md guidelines/core-principles.md"
TESTING="guidelines/testing-strategy.md guidelines/unit-testing.md guidelines/integration-testing.md"

# 1. Each path kind demands its routed set, and only that set.
check_kind "main java" k1 "$ALPHA/orders-core/src/main/java/com/example/orders/web/OrderController.java" \
  "$BASE guidelines/java-coding-conventions.md guidelines/project-structure.md"
check_kind "test java" k2 "$ALPHA/src/test/java/com/example/orders/service/OrderServiceTest.java" \
  "$BASE guidelines/java-coding-conventions.md $TESTING"
check_kind "test-named class under main" k3 "$ALPHA/src/main/java/com/example/FakeClockIT.java" \
  "$BASE guidelines/java-coding-conventions.md guidelines/project-structure.md"
check_kind "plain sql" k4 "$ALPHA/src/test/resources/seed-data.sql" \
  "$BASE guidelines/database-and-flyway.md"
check_kind "migration" k5 "$ALPHA/src/main/resources/db/migration/V202610081200__create_orders.sql" \
  "$BASE guidelines/database-and-flyway.md"
check_kind "pom" k6 "$ALPHA/orders-core/pom.xml" \
  "$BASE guidelines/project-structure.md"
check_kind "application config" k7 "$ALPHA/src/main/resources/application-dev.yml" \
  "$BASE guidelines/project-structure.md"
check_kind "other file" k8 "$ALPHA/README.md" "$BASE"

# 2. The block message quotes the reason from the route file.
run_pre "$(edit_payload r1 file_path "$ALPHA/src/main/java/A.java")"
assert_mentions "block message: quotes the route reason" "the layer packages and what each layer may import"
assert_mentions "block message: names the edited file" "$ALPHA/src/main/java/A.java"

# 3. Reading the base set alone unlocks nothing beyond the base set.
record_base b1
run_pre "$(edit_payload b1 file_path "$ALPHA/src/test/java/ATest.java")"
assert_blocked "base set alone: test edit still blocked"
assert_not_mentions "base set alone: GUIDELINES.md no longer missing" "$H/standards/GUIDELINES.md"

# 4. Every registered repository is guarded: ~/ and project-relative SOURCE_REPO,
#    a trailing slash, and the physical form of a path behind a symlink.
run_pre "$(edit_payload g1 file_path "$BETA/src/main/java/B.java")"
assert_blocked "second repo (~/ path): edit is blocked"
assert_mentions "second repo: names project-structure.md" "$H/standards/guidelines/project-structure.md"
run_pre "$(edit_payload g2 file_path "$GAMMA/pom.xml")"
assert_blocked "third repo (project-relative path): edit is blocked"
PHYSICAL_ALPHA="$(cd "$ALPHA" && pwd -P)/README.md"
ln -s "$ALPHA" "$SANDBOX/alpha-link"
run_pre "$(edit_payload g3 file_path "$SANDBOX/alpha-link/README.md")"
assert_blocked "symlinked path into a repo: edit is blocked"
run_pre "$(edit_payload g4 file_path "$PHYSICAL_ALPHA")"
assert_blocked "physical path of a repo: edit is blocked"
run_pre "$(edit_payload g5 file_path "$SANDBOX/src/other/../alpha-service/README.md")"
assert_blocked "path with ..: normalized before the check"
#    service.env is read by kit/scripts/lib/service-env.sh: key and value trimmed, the last
#    SOURCE_REPO line wins.
run_pre "$(edit_payload g6 file_path "$DELTA/pom.xml")"
assert_blocked "spaced SOURCE_REPO line (the last one): edit is blocked"
run_pre "$(edit_payload g7 file_path "$DELTA_OLD/pom.xml")"
assert_allowed "an earlier SOURCE_REPO line of the same file: not guarded"

# 5. Edits outside every registered repository are never blocked.
run_pre "$(edit_payload o1 file_path "$OUTSIDE/src/main/java/C.java")"
assert_allowed "unregistered repo: allowed with no reads"
run_pre "$(edit_payload o2 file_path "$H/projects/alpha/AGENTS.md")"
assert_allowed "harness file: allowed with no reads"
run_pre "$(edit_payload o3 file_path "$SANDBOX/src/alpha-service-old/A.java")"
assert_allowed "sibling with the repo name as a prefix: allowed"

# 6. The other target fields: notebook_path (NotebookEdit) and path (Copilot CLI),
#    and a relative path resolved against the payload's cwd.
run_pre "$(edit_payload f1 notebook_path "$ALPHA/notebooks/load.ipynb")"
assert_blocked "notebook_path field: blocked"
assert_mentions "notebook_path field: names the notebook" "$ALPHA/notebooks/load.ipynb"
run_pre "$(edit_payload f2 path "$ALPHA/src/main/java/A.java")"
assert_blocked "path field: blocked"
run_pre "$(printf '{"session_id":"f3","cwd":"%s","tool_input":{"file_path":"src/main/java/A.java"}}' "$ALPHA")"
assert_blocked "relative path with cwd in a repo: blocked"

# 7. Session reset: a new session id needs fresh reads.
for g in $BASE guidelines/java-coding-conventions.md guidelines/project-structure.md; do
  record_read s1 "$g"
done
run_pre "$(edit_payload s1 file_path "$ALPHA/src/main/java/A.java")"
assert_allowed "session reset: first session is allowed"
run_pre "$(edit_payload s2 file_path "$ALPHA/src/main/java/A.java")"
assert_blocked "session reset: a new session is blocked"

# 8. Fail closed: a payload the gate cannot parse but that names a registered
#    repository requires the base set; one that names none is let through.
run_pre "this is not json, but it names $BETA/src/main/java/B.java"
assert_blocked "unparsed payload naming a repo: blocked"
assert_mentions "unparsed payload: names GUIDELINES.md" "$H/standards/GUIDELINES.md"
assert_mentions "unparsed payload: names core-principles.md" "$H/standards/guidelines/core-principles.md"
assert_not_mentions "unparsed payload: no path route applies" "java-coding-conventions.md"
run_pre "$(printf '{"session_id":"u2","tool_input":{"content":"see %s/x.java"}}' "$ALPHA")"
assert_blocked "payload with no target field but a repo path: blocked"
run_pre "this is not json and names nothing the gate guards"
assert_allowed "unparsed payload naming no repo: allowed"

# 9. How a read is recognized.
#    A relative path counts when it resolves, against the payload's cwd, to a
#    file under the harness standards/. Other standards/ folders never count.
record_bash p1 "$H" "cat standards/GUIDELINES.md ./standards/guidelines/core-principles.md"
record_bash p1 "$H/standards" "sed -n 1,80p guidelines/java-coding-conventions.md"
record_bash p1 "$H/projects/alpha" "cat ../../standards/guidelines/project-structure.md"
run_pre "$(edit_payload p1 file_path "$ALPHA/src/main/java/A.java")"
assert_allowed "relative reads that resolve into the harness standards/: recorded"
record_bash p2 "$SANDBOX" "cat standards/GUIDELINES.md"
record_bash p2 "" "cat standards/guidelines/core-principles.md"
record_bash p2 "$H" "cat guidelines/java-coding-conventions.md"
record_bash p2 "$H" "cat /elsewhere/standards/guidelines/project-structure.md"
run_pre "$(edit_payload p2 file_path "$ALPHA/src/main/java/A.java")"
assert_blocked "relative reads outside the harness, look-alikes: not recorded"
assert_mentions "not recorded: GUIDELINES.md still missing" "$H/standards/GUIDELINES.md"
assert_mentions "not recorded: core-principles.md still missing" "$H/standards/guidelines/core-principles.md"
assert_mentions "not recorded: java-coding-conventions.md still missing" "$H/standards/guidelines/java-coding-conventions.md"
assert_mentions "not recorded: project-structure.md still missing" "$H/standards/guidelines/project-structure.md"
#    With no cwd in the payload, the gate's own working directory applies.
GATE_PWD="$H"
record_bash p5 "" "cat standards/GUIDELINES.md"
GATE_PWD="$SANDBOX"
run_pre "$(edit_payload p5 file_path "$ALPHA/README.md")"
assert_not_mentions "no cwd field: resolved against the gate's working directory" "$H/standards/GUIDELINES.md"
#    A ~/ path to the harness counts.
mkdir -p "$HOME/work"
ln -s "$H" "$HOME/work/harness"
record_bash p3 "" "cat ~/work/harness/standards/GUIDELINES.md"
run_pre "$(edit_payload p3 file_path "$ALPHA/README.md")"
assert_not_mentions "~/ path through a link to the harness: recorded" "$H/standards/GUIDELINES.md"
#    A glob is expanded against the harness standards/; each guideline it matches counts.
record_bash p6 "$H" "cat standards/GUIDELINES.md 'standards/guidelines/core-*.md' standards/guidelines/java-*"
run_pre "$(edit_payload p6 file_path "$ALPHA/src/main/java/A.java")"
assert_blocked "glob read: a guideline the glob does not match is still missing"
assert_not_mentions "glob read: a matched guideline is recorded" "$H/standards/guidelines/java-coding-conventions.md"
assert_not_mentions "glob read: a quoted glob is expanded" "$H/standards/guidelines/core-principles.md"
assert_mentions "glob read: project-structure.md still missing" "$H/standards/guidelines/project-structure.md"
record_bash p6 "$H/standards" "head -n 5 guidelines/*.md"
run_pre "$(edit_payload p6 file_path "$ALPHA/src/main/java/A.java")"
assert_allowed "glob read: guidelines/*.md from standards/ records every guideline"
record_bash p7 "$H" "cat $SANDBOX/src/*/standards/guidelines/*.md /elsewhere/standards/guidelines/*.md"
run_pre "$(edit_payload p7 file_path "$ALPHA/README.md")"
assert_mentions "glob outside the harness standards/: not recorded" "$H/standards/guidelines/core-principles.md"
#    What a tool returns is not a read: GUIDELINES.md and this test name every
#    guideline, so their text must not unlock the files it names.
run_gate "$GATE" post "$(printf '{"session_id":"p4","cwd":"%s/standards","tool_name":"Read","tool_input":{"file_path":"%s/standards/GUIDELINES.md"},"tool_response":{"file":{"content":"guidelines/java-coding-conventions.md %s/standards/guidelines/project-structure.md"}}}' "$H" "$H" "$H")"
run_pre "$(edit_payload p4 file_path "$ALPHA/src/main/java/A.java")"
assert_blocked "tool response text: not recorded"
assert_not_mentions "tool response: the file read itself is recorded" "$H/standards/GUIDELINES.md"
assert_mentions "tool response: a guideline it names is still missing" "$H/standards/guidelines/java-coding-conventions.md"
#    A post payload the gate cannot parse records nothing and never fails.
run_gate "$GATE" post "not json $H/standards/GUIDELINES.md"
assert_allowed "unparsed post payload: exit 0"

# 10. The routes are data: a new row in the route file is enforced with no
#     change to the gate.
printf '%s\n' '*/docs/*.md | guidelines/rest-api.md | you are editing service docs: the fixture row' >> "$H/standards/gate-routes.txt"
record_base d1
run_pre "$(edit_payload d1 file_path "$ALPHA/docs/api.md")"
assert_blocked "new route row: enforced"
assert_mentions "new route row: names its guideline" "$H/standards/guidelines/rest-api.md"
assert_mentions "new route row: quotes its reason" "you are editing service docs: the fixture row"
record_read d1 guidelines/rest-api.md
run_pre "$(edit_payload d1 file_path "$ALPHA/docs/api.md")"
assert_allowed "new route row: allowed once its guideline is read"

# 11. No route file: a guarded edit is blocked, an unguarded one is not.
mv "$H/standards/gate-routes.txt" "$H/standards/gate-routes.off"
record_base m1
run_pre "$(edit_payload m1 file_path "$ALPHA/README.md")"
assert_blocked "missing route file: guarded edit blocked"
assert_mentions "missing route file: says so" "gate-routes.txt"
run_pre "$(edit_payload m1 file_path "$OUTSIDE/README.md")"
assert_allowed "missing route file: unguarded edit allowed"
mv "$H/standards/gate-routes.off" "$H/standards/gate-routes.txt"

# 12. A harness with no projects/ folder guards nothing and does not crash.
H2="$SANDBOX/bare-harness"
make_harness "$H2"
run_gate "$H2/hooks/standards-gate.sh" pre "$(edit_payload n1 file_path "$ALPHA/README.md")"
assert_allowed "no projects/ folder: edit allowed"
if [ -z "$last_stderr" ]; then report ok "no projects/ folder: no error output"; else report fail "no projects/ folder: no error output" "$last_stderr"; fi

# 13. Without the service.env library the gate cannot read SOURCE_REPO. It blocks an edit
#     whose payload names the folder of any SOURCE_REPO value, and lets every other edit pass.
H3="$SANDBOX/no-lib-harness"
make_harness "$H3"
rm "$H3/kit/scripts/lib/service-env.sh"
cp -R "$H/projects" "$H3/projects"
run_gate "$H3/hooks/standards-gate.sh" pre "$(edit_payload l1 file_path "$ALPHA/README.md")"
assert_blocked "no service.env library: a guarded edit is blocked"
assert_mentions "no service.env library: says so" "kit/scripts/lib/service-env.sh"
run_gate "$H3/hooks/standards-gate.sh" pre "$(edit_payload l2 file_path "$BETA/src/A.java")"
assert_blocked "no service.env library: an edit in a ~/ repository is blocked"
run_gate "$H3/hooks/standards-gate.sh" pre "$(edit_payload l3 file_path "$OUTSIDE/README.md")"
assert_allowed "no service.env library: an edit outside every repository is allowed"
run_gate "$H3/hooks/standards-gate.sh" post "$(printf '{"session_id":"l4","tool_input":{"file_path":"%s/standards/GUIDELINES.md"}}' "$H3")"
assert_allowed "no service.env library: a post call still exits 0"

# 14. A missing or unknown mode is a usage error, not a pass.
run_gate "$GATE" "" "{}"
if [ "$last_code" != "0" ] && [ "$last_code" != "2" ]; then report ok "no mode: usage error"; else report fail "no mode: usage error" "got exit $last_code"; fi

# 15. The real route file passes its own check.
if bash "$REAL_ROOT/standards/check-routes.sh" "$REAL_ROOT/standards" >/dev/null; then
  report ok "real route file passes check-routes.sh"
else
  report fail "real route file passes check-routes.sh" "run bash standards/check-routes.sh"
fi

echo
echo "passed: $pass  failed: $fail"
[ "$fail" -eq 0 ]
