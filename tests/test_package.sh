#!/usr/bin/env bash
# test_package.sh — Unit tests for lib/package.sh failure propagation.
# Uses function stubs so no real package manager (or network) is ever touched.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

source "$SCRIPT_DIR/test_framework.sh"

# Isolated fake HOME so logs never touch the real ~/.env-setup
export HOME="${TEST_TMPDIR}/home"
mkdir -p "$HOME"
DRY_RUN="false"
AUTO_YES="true"

# shellcheck source=lib/common.sh
source "$PROJECT_ROOT/lib/common.sh"
# shellcheck source=lib/dryrun.sh
source "$PROJECT_ROOT/lib/dryrun.sh"
# shellcheck source=lib/package.sh
source "$PROJECT_ROOT/lib/package.sh"
setup_logging

# This suite asserts on non-zero exit codes; disable errexit like test_uninstall.
set +e

echo -e "${_T_BOLD}Test: Package failure propagation${_T_NC}"

# =============================================================================
# Stubs — simulate a Linux/apt box where the installer's outcome is scripted
# via _STUB_INSTALL_RC. Overriding sourced functions is plain bash.
# =============================================================================
is_macos() { return 1; }
is_linux() { return 0; }
sudo_available() { return 0; }
command_exists() { [[ "$1" == "apt-get" ]]; }
_STUB_INSTALL_RC=0
dry_run_cmd() { return "$_STUB_INSTALL_RC"; }

suite "pkg_install propagates installer failure"

_STUB_INSTALL_RC=0
pkg_install some-tool >/dev/null 2>&1
assert_true $? "returns 0 when the installer succeeds"

_STUB_INSTALL_RC=1
pkg_install some-tool >/dev/null 2>&1
assert_false $? "returns non-zero when apt-get install fails"

# One failing + one succeeding package still reports overall failure
_STUB_INSTALL_RC=1
pkg_install broken-tool >/dev/null 2>&1
assert_false $? "any failing package fails the batch"

suite "pkg_remove propagates removal failure"

_STUB_INSTALL_RC=0
pkg_remove some-tool >/dev/null 2>&1
assert_true $? "returns 0 when removal succeeds"

_STUB_INSTALL_RC=1
pkg_remove some-tool >/dev/null 2>&1
assert_false $? "returns non-zero when apt-get purge fails"

suite "no-sudo defer still counts as failure"

sudo_available() { return 1; }
_STUB_INSTALL_RC=0
pkg_install deferred-tool >/dev/null 2>&1
assert_false $? "deferred package returns non-zero"
assert_contains "${MISSING_APT_PACKAGES[*]}" "deferred-tool" "deferred package recorded for admin summary"
sudo_available() { return 0; }

suite "log_error increments ENVSETUP_ERROR_COUNT"

_before="${ENVSETUP_ERROR_COUNT:-0}"
log_error "counter check" >/dev/null 2>&1
assert_eq "$((_before + 1))" "${ENVSETUP_ERROR_COUNT:-0}" "log_error bumps the global error counter"

print_test_summary
