#!/usr/bin/env bash
# test_git_defaults.sh — 01-core.sh git defaults: the managed global-ignore
# block and rerere. Sandboxed through HOME (ignore file, marker) and
# GIT_CONFIG_GLOBAL (git >= 2.32) so the developer's real git config is never
# read for decisions or written.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

source "$SCRIPT_DIR/test_framework.sh"

# Re-point HOME BEFORE lib/common.sh binds LOG_DIR (source-time binding).
ORIG_HOME="$HOME"
export HOME="$TEST_TMPDIR/home"
mkdir -p "$HOME"
export GIT_CONFIG_GLOBAL="$HOME/.gitconfig"
: > "$GIT_CONFIG_GLOBAL"
unset XDG_CONFIG_HOME

source "$PROJECT_ROOT/lib/common.sh"
source "$PROJECT_ROOT/lib/yaml.sh"
source "$PROJECT_ROOT/lib/dryrun.sh"
source "$PROJECT_ROOT/lib/config.sh"
source "$PROJECT_ROOT/lib/package.sh"
source "$PROJECT_ROOT/lib/uninstall.sh"
setup_logging
load_config "$PROJECT_ROOT/config.yaml"
DRY_RUN="false"

# shellcheck source=modules/01-core.sh
source "$PROJECT_ROOT/modules/01-core.sh"

set +e

echo -e "${_T_BOLD}Test: 01-core.sh git defaults${_T_NC}"

if ! command -v git >/dev/null 2>&1; then
    skip "git not installed — git defaults suite not run"
    print_test_summary
    exit 0
fi

_ignore="$HOME/.config/git/ignore"
_marker="$HOME/.env-setup/.git-rerere-set"

# =============================================================================
suite "first run: ignore block + rerere"
# =============================================================================
_configure_git_defaults >/dev/null 2>&1
assert_file_exists "$_ignore" "global ignore created at ~/.config/git/ignore"
assert_contains "$(cat "$_ignore")" '**/.claude/settings.local.json' "ignore block carries the Claude Code entry"
assert_eq "true" "$(git config --global --get rerere.enabled)" "rerere.enabled set to true"
assert_file_exists "$_marker" "rerere marker recorded for uninstall"

# git itself must honour the entry inside a repo
mkdir -p "$TEST_TMPDIR/repo/.claude"
git -C "$TEST_TMPDIR/repo" init -q
: > "$TEST_TMPDIR/repo/.claude/settings.local.json"
git -C "$TEST_TMPDIR/repo" check-ignore -q .claude/settings.local.json
assert_true $? "git ignores .claude/settings.local.json in a repo"

# =============================================================================
suite "second run: idempotent"
# =============================================================================
_configure_git_defaults >/dev/null 2>&1
assert_eq "2" "$(grep -c 'env-setup managed' "$_ignore")" "block markers appear exactly once"

# =============================================================================
suite "pre-set rerere is left alone"
# =============================================================================
rm -f "$_marker"
git config --global rerere.enabled false
_configure_git_defaults >/dev/null 2>&1
assert_eq "false" "$(git config --global --get rerere.enabled)" "user's rerere.enabled=false preserved"
assert_file_not_exists "$_marker" "no marker when env-setup did not set rerere"
git config --global --unset rerere.enabled

# =============================================================================
suite "core.excludesFile is honoured"
# =============================================================================
git config --global core.excludesFile "$HOME/custom-ignore"
# Same-file test rather than string equality: Git Bash on Windows hands the
# path to git.exe in C:/ form, so the stored string differs from $HOME's form.
: > "$HOME/custom-ignore"
[[ "$(_git_global_ignore_path)" -ef "$HOME/custom-ignore" ]]
assert_true $? "resolves core.excludesFile"
_configure_git_defaults >/dev/null 2>&1
assert_contains "$(cat "$HOME/custom-ignore")" '**/.claude/settings.local.json' "block lands in the configured excludes file"
git config --global --unset core.excludesFile
git config --global --unset rerere.enabled
rm -f "$_marker" "$HOME/custom-ignore"

# =============================================================================
suite "dry run mutates nothing"
# =============================================================================
rm -f "$_ignore"
_out="$(DRY_RUN="true" _configure_git_defaults 2>&1)"
assert_contains "$_out" "[DRY-RUN]" "dry run announces the actions"
assert_file_not_exists "$_ignore" "dry run does not create the ignore file"
_rr="$(git config --global --get rerere.enabled || true)"
assert_eq "" "$_rr" "dry run does not set rerere"

# =============================================================================
suite "uninstall strips only what setup added"
# =============================================================================
mkdir -p "$(dirname "$_ignore")"
printf 'user-line\n' > "$_ignore"
_configure_git_defaults >/dev/null 2>&1
_unconfigure_git_defaults >/dev/null 2>&1
assert_contains "$(cat "$_ignore")" "user-line" "user's own ignore entries preserved"
assert_not_contains "$(cat "$_ignore")" "settings.local.json" "managed block removed"
_rr="$(git config --global --get rerere.enabled || true)"
assert_eq "" "$_rr" "rerere unset because env-setup had set it"
assert_file_not_exists "$_marker" "marker removed"

# A user-set rerere (no marker) survives uninstall
git config --global rerere.enabled false
_unconfigure_git_defaults >/dev/null 2>&1
assert_eq "false" "$(git config --global --get rerere.enabled)" "user-set rerere left alone on uninstall"

# Restore HOME so trap cleanup of TEST_TMPDIR can run normally
export HOME="$ORIG_HOME"
unset GIT_CONFIG_GLOBAL

print_test_summary
