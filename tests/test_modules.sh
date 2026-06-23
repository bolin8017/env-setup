#!/usr/bin/env bash
# test_modules.sh — Tests for module structure and integrity
# Verifies each module file exists and defines its expected entry function.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

source "$SCRIPT_DIR/test_framework.sh"
source "$PROJECT_ROOT/lib/common.sh"
source "$PROJECT_ROOT/lib/yaml.sh"
source "$PROJECT_ROOT/lib/dryrun.sh"
source "$PROJECT_ROOT/lib/package.sh"
source "$PROJECT_ROOT/lib/config.sh"

# Load config so cfg_* functions work inside modules
setup_logging
load_config "$PROJECT_ROOT/config.yaml"
DRY_RUN="true"
AUTO_YES="true"
export ENV_SETUP_DIR="$PROJECT_ROOT"

echo -e "${_T_BOLD}Test: Module Structure${_T_NC}"

# =============================================================================
suite "Module files exist"
# =============================================================================

declare -A MODULE_MAP=(
    ["01-core"]="install_core"
    ["02-languages"]="install_languages"
    ["03-python-tools"]="install_python_tools"
    ["04-docker"]="install_docker"
    ["05-cli-tools"]="install_cli_tools"
    ["06-shell"]="install_shell"
    ["07-tmux"]="install_tmux"
    ["08-claude-code"]="install_claude_code"
    ["09-user-dirs"]="install_user_dirs"
    ["10-worklog"]="install_worklog"
)

for module in "${!MODULE_MAP[@]}"; do
    assert_file_exists "$PROJECT_ROOT/modules/${module}.sh" "module file: ${module}.sh"
done

# =============================================================================
suite "Module entry functions are defined after sourcing"
# =============================================================================

for module in "${!MODULE_MAP[@]}"; do
    fn="${MODULE_MAP[$module]}"
    # shellcheck source=/dev/null
    source "$PROJECT_ROOT/modules/${module}.sh"

    if declare -f "$fn" &>/dev/null; then
        (( _TEST_TOTAL += 1 ))
        echo -e "  ${_T_GREEN}PASS${_T_NC}  ${module}.sh defines ${fn}()"
        (( _TEST_PASS += 1 ))
    else
        (( _TEST_TOTAL += 1 ))
        echo -e "  ${_T_RED}FAIL${_T_NC}  ${module}.sh does NOT define ${fn}()"
        (( _TEST_FAIL += 1 ))
    fi
done

# =============================================================================
suite "Uninstall entry functions are defined after sourcing"
# =============================================================================

declare -A UNINSTALL_MAP=(
    ["01-core"]="uninstall_core"
    ["02-languages"]="uninstall_languages"
    ["03-python-tools"]="uninstall_python_tools"
    ["04-docker"]="uninstall_docker"
    ["05-cli-tools"]="uninstall_cli_tools"
    ["06-shell"]="uninstall_shell"
    ["07-tmux"]="uninstall_tmux"
    ["08-claude-code"]="uninstall_claude_code"
    ["09-user-dirs"]="uninstall_user_dirs"
    ["10-worklog"]="uninstall_worklog"
)

# Every module file was already sourced by the install-functions suite above,
# so both install_* and uninstall_* are in scope — no re-source needed (and
# re-sourcing 05-cli-tools.sh would trip its `readonly CLI_TOOLS`).
for module in "${!UNINSTALL_MAP[@]}"; do
    fn="${UNINSTALL_MAP[$module]}"
    if declare -f "$fn" &>/dev/null; then
        (( _TEST_TOTAL += 1 )); echo -e "  ${_T_GREEN}PASS${_T_NC}  ${module}.sh defines ${fn}()"; (( _TEST_PASS += 1 ))
    else
        (( _TEST_TOTAL += 1 )); echo -e "  ${_T_RED}FAIL${_T_NC}  ${module}.sh does NOT define ${fn}()"; (( _TEST_FAIL += 1 ))
    fi
done

# =============================================================================
suite "Modules referenced in setup.sh match actual files"
# =============================================================================

# Extract run_module calls from setup.sh
while IFS= read -r line; do
    module_name="$(echo "$line" | sed -n 's/.*run_module "\([^"]*\)".*/\1/p')"
    [[ -z "$module_name" ]] && continue

    assert_file_exists "$PROJECT_ROOT/modules/${module_name}.sh" \
        "setup.sh references existing module: ${module_name}"
done < "$PROJECT_ROOT/setup.sh"

# =============================================================================
suite "No orphan module files (every file is referenced in setup.sh)"
# =============================================================================

for module_file in "$PROJECT_ROOT/modules"/*.sh; do
    module_name="$(basename "$module_file" .sh)"
    if grep -q "run_module \"${module_name}\"" "$PROJECT_ROOT/setup.sh"; then
        (( _TEST_TOTAL += 1 ))
        echo -e "  ${_T_GREEN}PASS${_T_NC}  ${module_name} is referenced in setup.sh"
        (( _TEST_PASS += 1 ))
    else
        (( _TEST_TOTAL += 1 ))
        echo -e "  ${_T_RED}FAIL${_T_NC}  ${module_name} is NOT referenced in setup.sh (orphan)"
        (( _TEST_FAIL += 1 ))
    fi
done

# =============================================================================
suite "Module numbering is sequential (no gaps)"
# =============================================================================

expected_num=1
for module_file in "$PROJECT_ROOT/modules"/*.sh; do
    module_name="$(basename "$module_file" .sh)"
    actual_num="$(echo "$module_name" | grep -oE '^[0-9]+' | sed 's/^0*//')"
    assert_eq "$expected_num" "$actual_num" "module $module_name has expected number $expected_num"
    (( expected_num += 1 ))
done

# =============================================================================
suite "Library files exist"
# =============================================================================

for lib_file in common.sh yaml.sh config.sh package.sh dryrun.sh backup.sh; do
    assert_file_exists "$PROJECT_ROOT/lib/${lib_file}" "lib/${lib_file}"
done

# =============================================================================
suite "Library double-source guards"
# =============================================================================

# Each lib file should have a guard variable
for lib_file in "$PROJECT_ROOT/lib"/*.sh; do
    name="$(basename "$lib_file")"
    if grep -q '_ENV_SETUP_.*_LOADED' "$lib_file"; then
        (( _TEST_TOTAL += 1 ))
        echo -e "  ${_T_GREEN}PASS${_T_NC}  ${name} has double-source guard"
        (( _TEST_PASS += 1 ))
    else
        (( _TEST_TOTAL += 1 ))
        echo -e "  ${_T_RED}FAIL${_T_NC}  ${name} missing double-source guard"
        (( _TEST_FAIL += 1 ))
    fi
done

# =============================================================================
suite "Language shell-init hardening (02-languages.sh)"
# =============================================================================

languages_src="$(cat "$PROJECT_ROOT/modules/02-languages.sh")"
# pyenv: both init forms must pass --no-rehash so an interrupted rehash's stale
# shims lock can't stall every future shell ~60s waiting on it.
assert_contains "$languages_src" "pyenv init --path --no-rehash" "pyenv: 'init --path' skips rehash"
assert_contains "$languages_src" "pyenv init - --no-rehash"      "pyenv: 'init -' skips rehash"
assert_not_contains "$languages_src" 'pyenv init --path)' "pyenv: no rehash-on-init via 'init --path'"
assert_not_contains "$languages_src" 'pyenv init -)'      "pyenv: no rehash-on-init via 'init -'"
# nvm: lazy-loaded so its auto-use does not run on every shell start.
assert_contains "$languages_src" "_envsetup_load_nvm" "nvm: lazy-load stubs defined"

# =============================================================================
suite "Oh My Zsh install idempotency (06-shell.sh)"
# =============================================================================

shell_src="$(cat "$PROJECT_ROOT/modules/06-shell.sh")"
# A half-installed ~/.oh-my-zsh (only custom/, left by the p10k/plugin clones
# when the core install failed) must be detected and repaired. Gate the
# "already installed" early-return on the core loader, not the bare directory.
assert_contains "$shell_src" 'if [[ -f "$omz_dir/oh-my-zsh.sh" ]]; then' \
    "install_oh_my_zsh: idempotency check probes oh-my-zsh.sh"
assert_not_contains "$shell_src" 'if [[ -d "$omz_dir" ]]; then
        log_info "Oh My Zsh already installed' \
    "install_oh_my_zsh: no bare-directory early return"

# =============================================================================
print_test_summary
