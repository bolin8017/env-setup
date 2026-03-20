#!/usr/bin/env bash
# run_docker_tests.sh — Build and run E2E tests in Docker containers
# Usage: bash tests/e2e/run_docker_tests.sh [--no-cache]
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

RED=$'\033[0;31m'
GREEN=$'\033[0;32m'
CYAN=$'\033[0;36m'
BOLD=$'\033[1m'
NC=$'\033[0m'

DOCKER_BUILD_ARGS=""
[[ "${1:-}" == "--no-cache" ]] && DOCKER_BUILD_ARGS="--no-cache"

if ! command -v docker &>/dev/null; then
    echo -e "${RED}Error: docker is required but not found${NC}"
    exit 1
fi

echo ""
echo -e "${CYAN}╔═══════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║${NC}  ${BOLD}env-setup — Docker E2E Test Runner${NC}                       ${CYAN}║${NC}"
echo -e "${CYAN}╚═══════════════════════════════════════════════════════════╝${NC}"
echo ""

passed=0
failed=0

run_test() {
    local name="$1"
    local dockerfile="$2"

    echo -e "${CYAN}━━━ Building ${BOLD}${name}${NC}"

    # Build
    if ! docker build \
        $DOCKER_BUILD_ARGS \
        -f "$SCRIPT_DIR/$dockerfile" \
        -t "env-setup-e2e-${name}" \
        "$PROJECT_ROOT" 2>&1 | tail -5; then
        echo -e "  ${RED}BUILD FAILED${NC}"
        (( failed += 1 ))
        return 1
    fi

    echo ""
    echo -e "${CYAN}━━━ Running ${BOLD}${name}${NC}"
    echo ""

    # Run (with timeout)
    if timeout 600 docker run --rm "env-setup-e2e-${name}" 2>&1; then
        echo -e "  ${GREEN}${BOLD}${name}: PASSED${NC}"
        (( passed += 1 ))
    else
        echo -e "  ${RED}${BOLD}${name}: FAILED${NC}"
        (( failed += 1 ))
    fi
    echo ""
}

# Run Ubuntu E2E
run_test "ubuntu" "Dockerfile.ubuntu"

# Summary
total=$(( passed + failed ))
echo -e "${CYAN}╔═══════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║${NC}  ${BOLD}E2E Summary: ${passed}/${total} platforms passed${NC}                     ${CYAN}║${NC}"
echo -e "${CYAN}╚═══════════════════════════════════════════════════════════╝${NC}"
echo ""

if [[ $failed -eq 0 ]]; then
    echo -e "  ${GREEN}${BOLD}ALL PLATFORMS PASSED${NC}"
else
    echo -e "  ${RED}${BOLD}${failed} PLATFORM(S) FAILED${NC}"
fi
echo ""

# Cleanup images
echo -e "${CYAN}Cleaning up Docker images...${NC}"
docker rmi env-setup-e2e-ubuntu 2>/dev/null || true
echo ""

[[ $failed -eq 0 ]]
