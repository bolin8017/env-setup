#!/usr/bin/env bash
# test_framework.sh — Minimal test framework for env-setup
# Provides assert functions and result tracking.
# Sourced by individual test files; not run directly.

set -euo pipefail

# Counters
_TEST_PASS=0
_TEST_FAIL=0
_TEST_TOTAL=0
_TEST_CURRENT_SUITE=""

# Colors
_T_RED=$'\033[0;31m'
_T_GREEN=$'\033[0;32m'
_T_YELLOW=$'\033[1;33m'
_T_CYAN=$'\033[0;36m'
_T_BOLD=$'\033[1m'
_T_NC=$'\033[0m'

# Temp directory for test artifacts (auto-cleaned)
TEST_TMPDIR=""
_setup_tmpdir() {
    TEST_TMPDIR="$(mktemp -d "/tmp/env-setup-test.XXXXXX")"
}
_cleanup_tmpdir() {
    [[ -n "${TEST_TMPDIR:-}" ]] && rm -rf "$TEST_TMPDIR"
}
trap _cleanup_tmpdir EXIT

# =============================================================================
# Test suite management
# =============================================================================
suite() {
    _TEST_CURRENT_SUITE="$1"
    echo ""
    echo -e "${_T_CYAN}━━━ ${_T_BOLD}$1${_T_NC}"
}

# =============================================================================
# Assertions
# =============================================================================

# assert_eq <expected> <actual> <message>
assert_eq() {
    local expected="$1" actual="$2" msg="$3"
    (( _TEST_TOTAL += 1 ))
    if [[ "$expected" == "$actual" ]]; then
        echo -e "  ${_T_GREEN}PASS${_T_NC}  $msg"
        (( _TEST_PASS += 1 ))
    else
        echo -e "  ${_T_RED}FAIL${_T_NC}  $msg"
        echo -e "        expected: ${_T_GREEN}${expected}${_T_NC}"
        echo -e "        actual:   ${_T_RED}${actual}${_T_NC}"
        (( _TEST_FAIL += 1 ))
    fi
}

# assert_neq <not_expected> <actual> <message>
assert_neq() {
    local not_expected="$1" actual="$2" msg="$3"
    (( _TEST_TOTAL += 1 ))
    if [[ "$not_expected" != "$actual" ]]; then
        echo -e "  ${_T_GREEN}PASS${_T_NC}  $msg"
        (( _TEST_PASS += 1 ))
    else
        echo -e "  ${_T_RED}FAIL${_T_NC}  $msg"
        echo -e "        should not be: ${_T_RED}${not_expected}${_T_NC}"
        (( _TEST_FAIL += 1 ))
    fi
}

# assert_contains <haystack> <needle> <message>
assert_contains() {
    local haystack="$1" needle="$2" msg="$3"
    (( _TEST_TOTAL += 1 ))
    if [[ "$haystack" == *"$needle"* ]]; then
        echo -e "  ${_T_GREEN}PASS${_T_NC}  $msg"
        (( _TEST_PASS += 1 ))
    else
        echo -e "  ${_T_RED}FAIL${_T_NC}  $msg"
        echo -e "        expected to contain: ${_T_GREEN}${needle}${_T_NC}"
        echo -e "        in: ${_T_RED}${haystack:0:200}${_T_NC}"
        (( _TEST_FAIL += 1 ))
    fi
}

# assert_not_contains <haystack> <needle> <message>
assert_not_contains() {
    local haystack="$1" needle="$2" msg="$3"
    (( _TEST_TOTAL += 1 ))
    if [[ "$haystack" != *"$needle"* ]]; then
        echo -e "  ${_T_GREEN}PASS${_T_NC}  $msg"
        (( _TEST_PASS += 1 ))
    else
        echo -e "  ${_T_RED}FAIL${_T_NC}  $msg"
        echo -e "        should not contain: ${_T_RED}${needle}${_T_NC}"
        (( _TEST_FAIL += 1 ))
    fi
}

# assert_true <exit_code> <message>
assert_true() {
    local exit_code="$1" msg="$2"
    (( _TEST_TOTAL += 1 ))
    if [[ "$exit_code" -eq 0 ]]; then
        echo -e "  ${_T_GREEN}PASS${_T_NC}  $msg"
        (( _TEST_PASS += 1 ))
    else
        echo -e "  ${_T_RED}FAIL${_T_NC}  $msg (exit code: $exit_code)"
        (( _TEST_FAIL += 1 ))
    fi
}

# assert_false <exit_code> <message>
assert_false() {
    local exit_code="$1" msg="$2"
    (( _TEST_TOTAL += 1 ))
    if [[ "$exit_code" -ne 0 ]]; then
        echo -e "  ${_T_GREEN}PASS${_T_NC}  $msg"
        (( _TEST_PASS += 1 ))
    else
        echo -e "  ${_T_RED}FAIL${_T_NC}  $msg (expected non-zero exit)"
        (( _TEST_FAIL += 1 ))
    fi
}

# assert_file_exists <path> <message>
assert_file_exists() {
    local path="$1" msg="$2"
    (( _TEST_TOTAL += 1 ))
    if [[ -f "$path" ]]; then
        echo -e "  ${_T_GREEN}PASS${_T_NC}  $msg"
        (( _TEST_PASS += 1 ))
    else
        echo -e "  ${_T_RED}FAIL${_T_NC}  $msg (not found: $path)"
        (( _TEST_FAIL += 1 ))
    fi
}

# assert_dir_exists <path> <message>
assert_dir_exists() {
    local path="$1" msg="$2"
    (( _TEST_TOTAL += 1 ))
    if [[ -d "$path" ]]; then
        echo -e "  ${_T_GREEN}PASS${_T_NC}  $msg"
        (( _TEST_PASS += 1 ))
    else
        echo -e "  ${_T_RED}FAIL${_T_NC}  $msg (not found: $path)"
        (( _TEST_FAIL += 1 ))
    fi
}

# assert_file_not_exists <path> <message>
assert_file_not_exists() {
    local path="$1" msg="$2"
    (( _TEST_TOTAL += 1 ))
    if [[ ! -e "$path" ]]; then
        echo -e "  ${_T_GREEN}PASS${_T_NC}  $msg"
        (( _TEST_PASS += 1 ))
    else
        echo -e "  ${_T_RED}FAIL${_T_NC}  $msg (exists: $path)"
        (( _TEST_FAIL += 1 ))
    fi
}

# =============================================================================
# Summary
# =============================================================================
print_test_summary() {
    echo ""
    echo -e "${_T_CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${_T_NC}"
    echo -e "  ${_T_GREEN}Passed:${_T_NC}  ${_TEST_PASS}"
    echo -e "  ${_T_RED}Failed:${_T_NC}  ${_TEST_FAIL}"
    echo -e "  ${_T_BOLD}Total:   ${_TEST_TOTAL}${_T_NC}"
    echo -e "${_T_CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${_T_NC}"
    echo ""
    [[ $_TEST_FAIL -eq 0 ]]
}

# Initialize tmpdir
_setup_tmpdir
