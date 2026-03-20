#!/usr/bin/env bash
# run_all.sh — Run all env-setup tests
# Usage: bash tests/run_all.sh
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

RED=$'\033[0;31m'
GREEN=$'\033[0;32m'
CYAN=$'\033[0;36m'
BOLD=$'\033[1m'
NC=$'\033[0m'

echo ""
echo -e "${CYAN}╔═══════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║${NC}  ${BOLD}env-setup — Test Suite${NC}                                   ${CYAN}║${NC}"
echo -e "${CYAN}╚═══════════════════════════════════════════════════════════╝${NC}"
echo ""

# Test files in execution order
tests=(
    "test_yaml_parser.sh"
    "test_common.sh"
    "test_dryrun.sh"
    "test_modules.sh"
    "test_config_consistency.sh"
    "test_fragments.sh"
    "test_shellcheck.sh"
)

total_suites=0
passed_suites=0
failed_suites=0
failed_names=()

for test_file in "${tests[@]}"; do
    test_path="${SCRIPT_DIR}/${test_file}"
    if [[ ! -f "$test_path" ]]; then
        echo -e "${RED}[MISS]${NC} ${test_file} — file not found"
        (( failed_suites += 1 ))
        failed_names+=("$test_file")
        (( total_suites += 1 ))
        continue
    fi

    echo -e "${CYAN}▶ Running ${BOLD}${test_file}${NC}"
    echo ""

    if bash "$test_path"; then
        (( passed_suites += 1 ))
    else
        (( failed_suites += 1 ))
        failed_names+=("$test_file")
    fi
    (( total_suites += 1 ))
done

# =============================================================================
# Grand summary
# =============================================================================
echo ""
echo -e "${CYAN}╔═══════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║${NC}  ${BOLD}Grand Summary${NC}                                            ${CYAN}║${NC}"
echo -e "${CYAN}╚═══════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "  ${GREEN}Passed suites:${NC} ${passed_suites}/${total_suites}"

if [[ ${#failed_names[@]} -gt 0 ]]; then
    echo -e "  ${RED}Failed suites:${NC} ${failed_suites}/${total_suites}"
    for name in "${failed_names[@]}"; do
        echo -e "    ${RED}✗${NC} $name"
    done
fi

echo ""

if [[ $failed_suites -eq 0 ]]; then
    echo -e "  ${GREEN}${BOLD}ALL TESTS PASSED${NC}"
else
    echo -e "  ${RED}${BOLD}SOME TESTS FAILED${NC}"
fi
echo ""

[[ $failed_suites -eq 0 ]]
