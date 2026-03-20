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
print_test_summary
