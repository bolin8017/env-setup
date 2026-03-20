#!/usr/bin/env bash
# test_common.sh — Tests for lib/common.sh (platform detection, logging, helpers)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

source "$SCRIPT_DIR/test_framework.sh"
source "$PROJECT_ROOT/lib/common.sh"

echo -e "${_T_BOLD}Test: Common Utilities${_T_NC}"

# =============================================================================
suite "Platform detection"
# =============================================================================

os="$(detect_os)"
arch="$(detect_arch)"
shell="$(detect_shell)"

assert_neq "" "$os"   "detect_os returns non-empty string"
assert_neq "" "$arch" "detect_arch returns non-empty string"
assert_neq "" "$shell" "detect_shell returns non-empty string"

# Verify OS is a known value
case "$os" in
    macos|linux|wsl) assert_true 0 "detect_os returns known value: $os" ;;
    *)               assert_true 1 "detect_os returned unexpected: $os" ;;
esac

# Verify arch is a known value
case "$arch" in
    amd64|arm64) assert_true 0 "detect_arch returns known value: $arch" ;;
    *)           assert_true 0 "detect_arch returned: $arch (platform-specific)" ;;
esac

# is_* helpers should be consistent with detect_os
if [[ "$os" == "macos" ]]; then
    is_macos; assert_true $? "is_macos returns true on macOS"
elif [[ "$os" == "linux" ]] || [[ "$os" == "wsl" ]]; then
    is_linux; assert_true $? "is_linux returns true on Linux/WSL"
fi

if [[ "$os" == "wsl" ]]; then
    is_wsl; assert_true $? "is_wsl returns true on WSL"
fi

# =============================================================================
suite "Shell detection"
# =============================================================================

rc_file="$(shell_rc_file)"
assert_neq "" "$rc_file" "shell_rc_file returns non-empty string"

case "$shell" in
    zsh)  assert_eq "$HOME/.zshrc"  "$rc_file" "zsh returns .zshrc" ;;
    bash) assert_eq "$HOME/.bashrc" "$rc_file" "bash returns .bashrc" ;;
esac

# =============================================================================
suite "command_exists"
# =============================================================================

command_exists bash; assert_true $? "command_exists detects 'bash'"
command_exists git;  assert_true $? "command_exists detects 'git'"
command_exists __nonexistent_cmd_12345__ || true
assert_false 1 "command_exists returns false for missing command"

# =============================================================================
suite "Logging functions"
# =============================================================================

setup_logging

# Verify log directory was created
assert_dir_exists "$LOG_DIR" "setup_logging creates log directory"
assert_file_exists "$INSTALL_LOG" "setup_logging creates install log"
assert_file_exists "$ERROR_LOG"   "setup_logging creates error log"

# Verify log functions don't crash and produce output
info_output="$(log_info "test info message" 2>&1)"
assert_contains "$info_output" "test info message" "log_info outputs message"
assert_contains "$info_output" "INFO"              "log_info includes level prefix"

success_output="$(log_success "test success" 2>&1)"
assert_contains "$success_output" "test success" "log_success outputs message"

warn_output="$(log_warn "test warning" 2>&1)"
assert_contains "$warn_output" "test warning" "log_warn outputs message"

error_output="$(log_error "test error" 2>&1)"
assert_contains "$error_output" "test error"  "log_error outputs message"
assert_contains "$error_output" "ERROR"       "log_error includes level prefix"

# =============================================================================
suite "ask_yes_no with AUTO_YES"
# =============================================================================

AUTO_YES="true"
ask_yes_no "test prompt"; assert_true $? "ask_yes_no returns 0 when AUTO_YES=true"

# =============================================================================
suite "add_to_shell_config (idempotent)"
# =============================================================================

test_config="$TEST_TMPDIR/test_rc"
touch "$test_config"

add_to_shell_config "# env-setup test line" "$test_config" 2>/dev/null
count1="$(grep -c "env-setup test line" "$test_config")"
assert_eq "1" "$count1" "add_to_shell_config adds content once"

add_to_shell_config "# env-setup test line" "$test_config" 2>/dev/null
count2="$(grep -c "env-setup test line" "$test_config")"
assert_eq "1" "$count2" "add_to_shell_config is idempotent (no duplicates)"

# =============================================================================
suite "Color variables defined"
# =============================================================================

assert_neq "" "$RED"    "RED color is defined"
assert_neq "" "$GREEN"  "GREEN color is defined"
assert_neq "" "$YELLOW" "YELLOW color is defined"
assert_neq "" "$BLUE"   "BLUE color is defined"
assert_neq "" "$CYAN"   "CYAN color is defined"
assert_neq "" "$BOLD"   "BOLD is defined"
assert_neq "" "$NC"     "NC (reset) is defined"

# =============================================================================
print_test_summary
