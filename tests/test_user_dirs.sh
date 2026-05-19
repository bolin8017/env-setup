#!/usr/bin/env bash
# test_user_dirs.sh — Unit tests for modules/09-user-dirs.sh `_create_user_dir`
# Validates schema-contract enforcement and idempotency.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

source "$SCRIPT_DIR/test_framework.sh"
source "$PROJECT_ROOT/lib/common.sh"
source "$PROJECT_ROOT/lib/yaml.sh"
source "$PROJECT_ROOT/lib/dryrun.sh"
source "$PROJECT_ROOT/lib/config.sh"

setup_logging
load_config "$PROJECT_ROOT/config.yaml"
DRY_RUN="false"   # we want real mkdir into TEST_TMPDIR

# Re-point HOME at the test tmp dir so we never touch the real $HOME
ORIG_HOME="$HOME"
export HOME="$TEST_TMPDIR"

# shellcheck source=/dev/null
source "$PROJECT_ROOT/modules/09-user-dirs.sh"

echo -e "${_T_BOLD}Test: 09-user-dirs.sh _create_user_dir${_T_NC}"

# ---------------------------------------------------------------------------
suite "Valid relative path creates directory"
# ---------------------------------------------------------------------------
_create_user_dir "subdir1" >/dev/null 2>&1
assert_dir_exists "$HOME/subdir1" "creates \$HOME/subdir1"

# ---------------------------------------------------------------------------
suite "Nested relative path creates parents"
# ---------------------------------------------------------------------------
_create_user_dir "a/b/c" >/dev/null 2>&1
assert_dir_exists "$HOME/a/b/c" "creates nested \$HOME/a/b/c"

# ---------------------------------------------------------------------------
suite "Idempotent when directory already exists"
# ---------------------------------------------------------------------------
mkdir -p "$HOME/existing-dir"
set +e
_create_user_dir "existing-dir" >/dev/null 2>&1
ec=$?
set -e
assert_eq "0" "$ec" "returns 0 when dir already exists"
assert_dir_exists "$HOME/existing-dir" "directory still exists after call"

# ---------------------------------------------------------------------------
suite "Absolute path is rejected"
# ---------------------------------------------------------------------------
out="$(_create_user_dir "/tmp/should-not-be-created" 2>&1 || true)"
assert_contains "$out" "WARN" "logs WARN for absolute path"
assert_file_not_exists "/tmp/should-not-be-created" "did not create absolute path"

# ---------------------------------------------------------------------------
suite "Path containing '..' is rejected"
# ---------------------------------------------------------------------------
out="$(_create_user_dir "../escapee" 2>&1 || true)"
assert_contains "$out" "WARN" "logs WARN for '..' path"
# The escape target would be $HOME/../escapee == parent of TEST_TMPDIR/escapee
assert_file_not_exists "$(dirname "$HOME")/escapee" "did not create escape path"

# ---------------------------------------------------------------------------
suite "Path starting with ~/ is rejected"
# ---------------------------------------------------------------------------
# shellcheck disable=SC2088  # passing literal '~/' as the input under test
out="$(_create_user_dir "~/literal-tilde" 2>&1 || true)"
assert_contains "$out" "WARN" "logs WARN for ~/ prefix"
assert_file_not_exists "$HOME/~" "did not create literal ~ dir"

# ---------------------------------------------------------------------------
suite "Refuses to clobber existing non-directory"
# ---------------------------------------------------------------------------
mkdir -p "$HOME/conflict-parent"
: > "$HOME/conflict-parent/file"
out="$(_create_user_dir "conflict-parent/file" 2>&1 || true)"
assert_contains "$out" "WARN" "logs WARN when target is a file"
# The file must still be a regular file, not converted to a dir
(( _TEST_TOTAL += 1 ))
if [[ -f "$HOME/conflict-parent/file" ]] && [[ ! -d "$HOME/conflict-parent/file" ]]; then
    echo -e "  ${_T_GREEN}PASS${_T_NC}  file preserved (still a regular file)"
    (( _TEST_PASS += 1 ))
else
    echo -e "  ${_T_RED}FAIL${_T_NC}  file was clobbered"
    (( _TEST_FAIL += 1 ))
fi

# Restore HOME so trap cleanup of TEST_TMPDIR can run normally
export HOME="$ORIG_HOME"

print_test_summary
