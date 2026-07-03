#!/usr/bin/env bash
# test_dryrun.sh — Tests for dry-run mode safety
# Verifies that dry-run mode does NOT modify the filesystem.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

source "$SCRIPT_DIR/test_framework.sh"
source "$PROJECT_ROOT/lib/common.sh"

# Force dry-run for dryrun.sh
DRY_RUN="true"
source "$PROJECT_ROOT/lib/dryrun.sh"

echo -e "${_T_BOLD}Test: Dry-Run Safety${_T_NC}"

# =============================================================================
suite "dry_run_cmd does not execute"
# =============================================================================

marker_file="$TEST_TMPDIR/should_not_exist"
dry_run_cmd touch "$marker_file" 2>/dev/null
assert_file_not_exists "$marker_file" "dry_run_cmd does not create files"

output="$(dry_run_cmd echo "hello" 2>&1)"
assert_contains "$output" "[DRY-RUN]" "dry_run_cmd prints DRY-RUN prefix"
assert_contains "$output" "echo hello" "dry_run_cmd shows the command"

# =============================================================================
suite "dry_run_cp does not copy"
# =============================================================================

src_file="$TEST_TMPDIR/source_file"
dst_file="$TEST_TMPDIR/dest_file"
echo "test content" > "$src_file"

output="$(dry_run_cp "$src_file" "$dst_file" 2>&1)"
assert_file_not_exists "$dst_file"   "dry_run_cp does not create destination"
assert_contains "$output" "[DRY-RUN]" "dry_run_cp prints DRY-RUN prefix"

# =============================================================================
suite "dry_run_mkdir does not create directories"
# =============================================================================

new_dir="$TEST_TMPDIR/should_not_exist_dir/nested"
output="$(dry_run_mkdir "$new_dir" 2>&1)"
assert_file_not_exists "$new_dir"    "dry_run_mkdir does not create directory"
assert_contains "$output" "[DRY-RUN]" "dry_run_mkdir prints DRY-RUN prefix"

# =============================================================================
suite "deploy_config in dry-run does not copy"
# =============================================================================

source "$PROJECT_ROOT/lib/dryrun.sh"
# deploy_config uses ask_yes_no, so set AUTO_YES
AUTO_YES="true"

deploy_src="$TEST_TMPDIR/deploy_src.conf"
deploy_dst="$TEST_TMPDIR/deploy_dst.conf"
echo "config content" > "$deploy_src"

setup_logging
output="$(deploy_config "$deploy_src" "$deploy_dst" "test-config" 2>&1)"
assert_file_not_exists "$deploy_dst" "deploy_config in dry-run does not create destination"

# =============================================================================
suite "Real mode (DRY_RUN=false) executes commands"
# =============================================================================

DRY_RUN="false"

real_file="$TEST_TMPDIR/real_file"
dry_run_cmd touch "$real_file"
assert_file_exists "$real_file" "dry_run_cmd executes when DRY_RUN=false"

real_src="$TEST_TMPDIR/real_src"
real_dst="$TEST_TMPDIR/real_dst"
echo "content" > "$real_src"
dry_run_cp "$real_src" "$real_dst"
assert_file_exists "$real_dst" "dry_run_cp copies when DRY_RUN=false"

real_dir="$TEST_TMPDIR/real_dir/nested"
dry_run_mkdir "$real_dir"
assert_dir_exists "$real_dir" "dry_run_mkdir creates dir when DRY_RUN=false"

# Reset
DRY_RUN="true"

# =============================================================================
suite "Full dry-run: setup.sh does not modify HOME"
# =============================================================================

# Sandboxed HOME: if dry-run has a leak, it damages the sandbox and the test
# fails — never the developer's real dotfiles (which this suite previously
# risked by running against the real \$HOME and checksumming only 3 files).
_dr_home="$TEST_TMPDIR/dryrun_home"
mkdir -p "$_dr_home"
printf 'user zshrc
'  > "$_dr_home/.zshrc"
printf 'user tmux
'   > "$_dr_home/.tmux.conf"
printf 'user p10k
'   > "$_dr_home/.p10k.zsh"

HOME="$_dr_home" bash "$PROJECT_ROOT/setup.sh" --dry-run --auto-yes &>/dev/null || true

assert_eq "user zshrc" "$(cat "$_dr_home/.zshrc")"      "dry-run leaves .zshrc untouched"
assert_eq "user tmux"  "$(cat "$_dr_home/.tmux.conf")"  "dry-run leaves .tmux.conf untouched"
assert_eq "user p10k"  "$(cat "$_dr_home/.p10k.zsh")"   "dry-run leaves .p10k.zsh untouched"

# Dry-run must not report phantom install failures for tools that were
# (correctly) not installed, and must not evaluate $(curl ...) eagerly.
_dr_out="$(HOME="$_dr_home" bash "$PROJECT_ROOT/setup.sh" --dry-run --auto-yes 2>&1 || true)"
assert_not_contains "$_dr_out" "installation failed" "dry-run reports no phantom install failures"

_eager="$(grep -l 'dry_run_cmd.*"\$(curl' "$PROJECT_ROOT"/modules/*.sh 2>/dev/null || true)"
assert_eq "" "$_eager" "no module evaluates \$(curl ...) before dry_run_cmd sees it"

# Nothing new may appear anywhere in the sandbox except the log dir
_unexpected="$(cd "$_dr_home" && find . -path ./.env-setup -prune -o -type f -print     | grep -v -e '^\./\.zshrc$' -e '^\./\.tmux\.conf$' -e '^\./\.p10k\.zsh$' || true)"
assert_eq "" "$_unexpected" "dry-run creates no files outside ~/.env-setup logs"

# =============================================================================
suite "dry_run_rm"
# =============================================================================

# Real removal when DRY_RUN is off
DRY_RUN="false"
_rmfile="${TEST_TMPDIR}/to_remove.txt"
echo "x" > "$_rmfile"
dry_run_rm "$_rmfile"
assert_file_not_exists "$_rmfile" "dry_run_rm removes the file when DRY_RUN=false"

# Prints, does not remove, when DRY_RUN is on
DRY_RUN="true"
_keepfile="${TEST_TMPDIR}/keep.txt"
echo "x" > "$_keepfile"
_out="$(dry_run_rm "$_keepfile")"
assert_contains "$_out" "[DRY-RUN] Would remove" "dry_run_rm prints in dry-run mode"
assert_file_exists "$_keepfile" "dry_run_rm does not remove the file in dry-run mode"
DRY_RUN="false"

# =============================================================================
suite "write_generated_fragment content-compares"
# =============================================================================

_frag_home="$TEST_TMPDIR/frag_home"
mkdir -p "$_frag_home"
_frag="$_frag_home/.config/zsh/fragments/16-nvm.zsh"

# Creates the fragment when absent
HOME="$_frag_home" DRY_RUN="false" write_generated_fragment "16-nvm.zsh" << 'CONTENT' >/dev/null
export NVM_DIR="$HOME/.nvm"
CONTENT
assert_file_exists "$_frag" "creates fragment when absent"
assert_contains "$(cat "$_frag")" "NVM_DIR" "fragment carries the content"

# Identical content -> no rewrite (no log output)
_out="$(HOME="$_frag_home" DRY_RUN="false" write_generated_fragment "16-nvm.zsh" << 'CONTENT'
export NVM_DIR="$HOME/.nvm"
CONTENT
)"
assert_not_contains "$_out" "fragment" "identical content is a silent no-op"

# Stale content -> UPDATED in place (the self-update regression: the old
# marker-grep guard never refreshed an existing fragment)
HOME="$_frag_home" DRY_RUN="false" write_generated_fragment "16-nvm.zsh" << 'CONTENT' >/dev/null
export NVM_DIR="$HOME/.nvm"
# v2 adds eager node on PATH
CONTENT
assert_contains "$(cat "$_frag")" "eager node" "stale fragment is refreshed with new content"

# Dry-run: differing content is reported but not written
_out="$(HOME="$_frag_home" DRY_RUN="true" write_generated_fragment "16-nvm.zsh" << 'CONTENT'
totally different
CONTENT
)"
assert_contains "$_out" "[DRY-RUN]" "dry-run announces the write"
assert_contains "$(cat "$_frag")" "eager node" "dry-run leaves the file untouched"

# =============================================================================
print_test_summary
