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

# Take a snapshot of key files before dry-run
declare -A checksums_before
for f in "$HOME/.zshrc" "$HOME/.tmux.conf" "$HOME/.p10k.zsh"; do
    if [[ -f "$f" ]]; then
        checksums_before["$f"]="$(md5sum "$f" | cut -d' ' -f1)"
    else
        checksums_before["$f"]="MISSING"
    fi
done

# Run setup.sh --dry-run --auto-yes (capture output, ignore exit code)
bash "$PROJECT_ROOT/setup.sh" --dry-run --auto-yes &>/dev/null || true

# Verify nothing changed
all_same=true
for f in "${!checksums_before[@]}"; do
    if [[ -f "$f" ]]; then
        after="$(md5sum "$f" | cut -d' ' -f1)"
    else
        after="MISSING"
    fi
    if [[ "${checksums_before[$f]}" != "$after" ]]; then
        echo -e "  ${_T_RED}CHANGED${_T_NC}: $f"
        all_same=false
    fi
done

(( _TEST_TOTAL += 1 ))
if $all_same; then
    echo -e "  ${_T_GREEN}PASS${_T_NC}  setup.sh --dry-run does not modify dotfiles"
    (( _TEST_PASS += 1 ))
else
    echo -e "  ${_T_RED}FAIL${_T_NC}  setup.sh --dry-run modified dotfiles!"
    (( _TEST_FAIL += 1 ))
fi

# =============================================================================
print_test_summary
