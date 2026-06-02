#!/usr/bin/env bash
# test_uninstall.sh — Unit tests for the uninstall safety primitives.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

source "$SCRIPT_DIR/test_framework.sh"

# Use an isolated fake HOME so nothing real is ever touched.
export HOME="${TEST_TMPDIR}/home"
mkdir -p "$HOME"
export ENV_SETUP_DIR="$PROJECT_ROOT"
DRY_RUN="false"
AUTO_YES="true"

# shellcheck source=lib/common.sh
source "$PROJECT_ROOT/lib/common.sh"
# shellcheck source=lib/dryrun.sh
source "$PROJECT_ROOT/lib/dryrun.sh"
# shellcheck source=lib/uninstall.sh
source "$PROJECT_ROOT/lib/uninstall.sh"

# test_framework.sh enables `set -e`; this suite deliberately runs commands that
# return non-zero (the assert_false cases capture $?), so disable errexit here.
set +e

echo -e "${_T_BOLD}Test: Uninstall primitives${_T_NC}"

suite "is_protected_path"

is_protected_path "$HOME"; assert_true $? "\$HOME itself is protected"
is_protected_path "$HOME/.env-setup/backups"; assert_true $? "backups dir is protected"
is_protected_path "$HOME/.env-setup/backups/backup_x/file"; assert_true $? "path under backups is protected"
is_protected_path "$HOME/.claude/.credentials.json"; assert_true $? "claude credentials protected"
is_protected_path "$HOME/.claude/projects/foo"; assert_true $? "claude projects protected"
is_protected_path "$HOME/.zshrc"; assert_false $? "HOME/.zshrc is not protected"
is_protected_path "$HOME/.claude/CLAUDE.md"; assert_false $? "HOME/.claude/CLAUDE.md is not protected"

PROTECTED_EXTRA="$HOME/Documents"$'\n'"$HOME/Downloads"
is_protected_path "$HOME/Documents"; assert_true $? "extra protected path matches"
is_protected_path "$HOME/Documents/repos/x"; assert_true $? "path under extra protected matches"
is_protected_path "$HOME/Tools"; assert_false $? "non-listed dir not protected"
PROTECTED_EXTRA=""

print_test_summary
