#!/usr/bin/env bash
# test_shellcheck.sh — Run shellcheck on all shell scripts
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

source "$SCRIPT_DIR/test_framework.sh"

echo -e "${_T_BOLD}Test: ShellCheck Lint${_T_NC}"

# =============================================================================
suite "shellcheck availability"
# =============================================================================

if ! command -v shellcheck &>/dev/null; then
    echo -e "  ${_T_YELLOW}SKIP${_T_NC}  shellcheck not installed"
    echo ""
    echo "Install with: sudo apt-get install shellcheck"
    exit 0
fi

(( _TEST_TOTAL += 1 ))
echo -e "  ${_T_GREEN}PASS${_T_NC}  shellcheck is available ($(shellcheck --version | grep '^version:' | awk '{print $2}'))"
(( _TEST_PASS += 1 ))

# =============================================================================
suite "Lint all shell scripts"
# =============================================================================

# Collect all .sh files
scripts=(
    "$PROJECT_ROOT/setup.sh"
    "$PROJECT_ROOT/bootstrap.sh"
)

for f in "$PROJECT_ROOT/lib"/*.sh; do
    scripts+=("$f")
done

for f in "$PROJECT_ROOT/modules"/*.sh; do
    scripts+=("$f")
done

for f in "$PROJECT_ROOT/scripts"/*.sh; do
    [[ -f "$f" ]] && scripts+=("$f")
done

# Run shellcheck on each file individually for granular reporting
for script in "${scripts[@]}"; do
    name="$(basename "$script")"
    (( _TEST_TOTAL += 1 ))
    if sc_output="$(shellcheck -x "$script" 2>&1)"; then
        echo -e "  ${_T_GREEN}PASS${_T_NC}  ${name}"
        (( _TEST_PASS += 1 ))
    else
        echo -e "  ${_T_RED}FAIL${_T_NC}  ${name}"
        echo "$sc_output" | head -20 | sed 's/^/        /'
        (( _TEST_FAIL += 1 ))
    fi
done

# =============================================================================
print_test_summary
