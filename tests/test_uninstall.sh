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

suite "remove_managed_file"

_repo="${TEST_TMPDIR}/repo_src.txt"
printf 'line1\nline2\n' > "$_repo"

# Identical copy → removed
_dest="$HOME/.identical"
cp "$_repo" "$_dest"
remove_managed_file "$_dest" "$_repo" "identical" >/dev/null
assert_file_not_exists "$_dest" "removes a file identical to repo source"

# Locally modified → preserved
_dest2="$HOME/.modified"
printf 'line1\nCHANGED\n' > "$_dest2"
remove_managed_file "$_dest2" "$_repo" "modified" >/dev/null
assert_file_exists "$_dest2" "preserves a locally-modified file"

# Missing dest → no-op success
remove_managed_file "$HOME/.nope" "$_repo" "missing"; assert_true $? "missing dest is a no-op"

# Protected dest → refused
PROTECTED_EXTRA="$HOME/Documents"
mkdir -p "$HOME/Documents"; echo y > "$HOME/Documents/keep"
cp "$_repo" "$HOME/Documents/managed"
remove_managed_file "$HOME/Documents/managed" "$_repo" "in-protected" >/dev/null
assert_file_exists "$HOME/Documents/managed" "refuses to remove inside a protected path"
PROTECTED_EXTRA=""

suite "remove_managed_dir"

AUTO_YES="true"   # skip the confirmation prompt
_d="$HOME/.toolclone"
mkdir -p "$_d/sub"; echo x > "$_d/sub/f"
remove_managed_dir "$_d" "toolclone" >/dev/null
assert_file_not_exists "$_d" "removes a tool directory (auto-yes)"

remove_managed_dir "$HOME/.absent" "absent"; assert_true $? "missing dir is a no-op"

PROTECTED_EXTRA="$HOME/Documents"
mkdir -p "$HOME/Documents"
remove_managed_dir "$HOME/Documents" "docs" >/dev/null
assert_dir_exists "$HOME/Documents" "refuses to remove a protected dir"
PROTECTED_EXTRA=""

suite "remove_fragment and strip_block_from_file"

_frags="$HOME/.config/zsh/fragments"
mkdir -p "$_frags"

# Marker present → removed
printf 'export PYENV_ROOT=/home/u/.pyenv\n' > "$_frags/15-pyenv.zsh"
remove_fragment "15-pyenv.zsh" "PYENV_ROOT" >/dev/null
assert_file_not_exists "$_frags/15-pyenv.zsh" "removes fragment when marker matches"

# Marker absent → preserved
printf 'something else\n' > "$_frags/16-nvm.zsh"
remove_fragment "16-nvm.zsh" "NVM_DIR" >/dev/null
assert_file_exists "$_frags/16-nvm.zsh" "preserves fragment when marker is missing"

# strip_block_from_file removes the conda block, keeps surrounding lines
_rc="$HOME/.bashrc"
printf 'before\n# >>> conda initialize >>>\nX\nY\n# <<< conda initialize <<<\nafter\n' > "$_rc"
strip_block_from_file "$_rc" "# >>> conda initialize >>>" "# <<< conda initialize <<<" >/dev/null
_body="$(cat "$_rc")"
assert_contains "$_body" "before" "keeps lines before the block"
assert_contains "$_body" "after" "keeps lines after the block"
assert_not_contains "$_body" "conda initialize" "removes the conda block"

suite "uninstall_core is defined and dry-runs cleanly"

# shellcheck source=/dev/null
source "$PROJECT_ROOT/modules/01-core.sh"
if declare -f uninstall_core >/dev/null; then assert_true 0 "uninstall_core defined"
else assert_true 1 "uninstall_core defined"; fi

DRY_RUN="true"
_out="$(uninstall_core 2>&1)"
assert_contains "$_out" "Uninstall: Core" "uninstall_core prints its header"
DRY_RUN="false"

suite "claude settings strip (no jq → skip gracefully)"

if command -v jq >/dev/null 2>&1; then
    # Load config so cfg_list "claude_code.settings_merge_keys" resolves
    source "$PROJECT_ROOT/lib/yaml.sh"
    source "$PROJECT_ROOT/lib/config.sh"
    setup_logging
    load_config "$PROJECT_ROOT/config.yaml" >/dev/null 2>&1
    source "$PROJECT_ROOT/modules/08-claude-code.sh"

    mkdir -p "$HOME/.claude"
    # 'env' is a whitelisted key; build it to MATCH the repo so the strip is
    # eligible to remove it. 'authToken' is user-owned and must survive.
    _repo_env="$(jq -c '.env' "$PROJECT_ROOT/configs/claude/settings.json")"
    jq -n --argjson env "$_repo_env" '{env:$env, authToken:"keepme"}' > "$HOME/.claude/settings.json"
    DRY_RUN="false"
    _uninstall_claude_settings >/dev/null 2>&1
    _after="$(cat "$HOME/.claude/settings.json")"
    assert_contains "$_after" "keepme" "user-owned authToken survives settings strip"
    assert_not_contains "$_after" "\"env\"" "whitelisted env key (== repo) is stripped"
else
    assert_true 0 "jq absent — settings strip test skipped"
fi

print_test_summary
