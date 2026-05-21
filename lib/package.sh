#!/usr/bin/env bash
# package.sh — Cross-platform package management abstraction
# Wraps brew/apt with a unified interface (dnf/yum fallback for pkg_install only).
# On Linux, detects sudo availability up front so installations on no-sudo
# machines fail fast and are summarised for an administrator at the end of
# setup. The password is prompted once via `sudo -v` and refreshed by a
# background keepalive so subsequent sudo calls don't re-prompt.
# Respects dry-run mode.

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    set -euo pipefail
fi

[[ -n "${_ENV_SETUP_PACKAGE_LOADED:-}" ]] && return 0
_ENV_SETUP_PACKAGE_LOADED=1

_PACKAGE_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${_PACKAGE_LIB_DIR}/common.sh"
# shellcheck source=lib/dryrun.sh
source "${_PACKAGE_LIB_DIR}/dryrun.sh"

# =============================================================================
# Sudo availability & credential keepalive
# =============================================================================
# sudo_available() detects elevation rights once and caches the result:
#   1. macOS / DRY_RUN → assume available (brew handles macOS; dry-run prints).
#   2. Cached or passwordless sudo (`sudo -n true`) → available.
#   3. Non-TTY or AUTO_YES → unavailable (don't prompt in batch mode).
#   4. Otherwise → `sudo -v` once. sudo reads the password directly from the
#      TTY via getpass(); this script never sees, logs, or stores it.
#
# On success, a background loop refreshes the sudo timestamp every 60s so
# subsequent sudo calls during long installs don't re-prompt. The loop is
# torn down by an EXIT trap when this shell exits.
#
# On failure, callers should record what they would have installed via
# record_missing_apt_package / record_missing_apt_note. show_missing_apt_summary
# prints the consolidated instructions for the administrator.

declare -ga MISSING_APT_PACKAGES=()
declare -ga MISSING_APT_NOTES=()

_SUDO_CHECKED=""
_SUDO_AVAILABLE=""
_SUDO_KEEPALIVE_PID=""

sudo_available() {
    # Dry-run and macOS skip the sudo path entirely
    if [[ "${DRY_RUN:-false}" == "true" ]] || is_macos; then
        return 0
    fi

    if [[ -n "$_SUDO_CHECKED" ]]; then
        [[ "$_SUDO_AVAILABLE" == "true" ]]
        return
    fi
    _SUDO_CHECKED=1

    if ! command_exists sudo; then
        log_warn "sudo not installed — apt installs will be deferred to administrator"
        _SUDO_AVAILABLE="false"
        return 1
    fi

    # Already cached / passwordless
    if sudo -n true 2>/dev/null; then
        _SUDO_AVAILABLE="true"
        _start_sudo_keepalive
        return 0
    fi

    # Batch / non-interactive: don't prompt
    if ! [[ -t 0 ]] || [[ "${AUTO_YES:-false}" == "true" ]]; then
        log_warn "sudo needs a password but no TTY (or --auto-yes) — apt installs will be deferred"
        _SUDO_AVAILABLE="false"
        return 1
    fi

    log_info "Some packages need sudo. Enter your password once (it is not stored)."
    if sudo -v; then
        _SUDO_AVAILABLE="true"
        _start_sudo_keepalive
        return 0
    fi

    log_warn "Could not acquire sudo — apt installs will be deferred to administrator"
    _SUDO_AVAILABLE="false"
    return 1
}

_start_sudo_keepalive() {
    [[ -n "$_SUDO_KEEPALIVE_PID" ]] && return 0

    # Refresh the sudo timestamp every 60s. The loop exits when the timestamp
    # can no longer be refreshed or when the parent shell ($$) is gone.
    (
        while sudo -n true 2>/dev/null; do
            sleep 60
            kill -0 "$$" 2>/dev/null || exit 0
        done
    ) &
    _SUDO_KEEPALIVE_PID=$!
    trap '_stop_sudo_keepalive' EXIT
}

_stop_sudo_keepalive() {
    [[ -z "$_SUDO_KEEPALIVE_PID" ]] && return 0
    kill "$_SUDO_KEEPALIVE_PID" 2>/dev/null || true
    _SUDO_KEEPALIVE_PID=""
}

# =============================================================================
# Missing-package / missing-step recording (used when sudo is unavailable)
# =============================================================================
record_missing_apt_package() {
    local pkg existing found
    for pkg in "$@"; do
        found=false
        if (( ${#MISSING_APT_PACKAGES[@]} > 0 )); then
            for existing in "${MISSING_APT_PACKAGES[@]}"; do
                if [[ "$existing" == "$pkg" ]]; then
                    found=true
                    break
                fi
            done
        fi
        [[ "$found" == "false" ]] && MISSING_APT_PACKAGES+=("$pkg")
    done
}

record_missing_apt_note() {
    local note="$1"
    local existing
    if (( ${#MISSING_APT_NOTES[@]} > 0 )); then
        for existing in "${MISSING_APT_NOTES[@]}"; do
            [[ "$existing" == "$note" ]] && return 0
        done
    fi
    MISSING_APT_NOTES+=("$note")
}

show_missing_apt_summary() {
    local n=${#MISSING_APT_PACKAGES[@]}
    local m=${#MISSING_APT_NOTES[@]}
    (( n + m == 0 )) && return 0

    echo ""
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BOLD}${BLUE}  Administrator Action Required${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo "  Sudo is unavailable on this machine. Please ask your"
    echo "  administrator to run the following:"
    echo ""

    if (( n > 0 )); then
        echo -e "  ${CYAN}# apt packages${NC}"
        echo "  sudo apt-get update"
        echo "  sudo apt-get install -y ${MISSING_APT_PACKAGES[*]}"
        echo ""
    fi

    if (( m > 0 )); then
        echo -e "  ${CYAN}# additional setup${NC}"
        local note
        for note in "${MISSING_APT_NOTES[@]}"; do
            echo "  - ${note}"
        done
        echo ""
    fi

    echo "  After installation, re-run ./setup.sh to continue."
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
}

# =============================================================================
# pkg_update — Update package manager index
# =============================================================================
pkg_update() {
    if is_macos; then
        dry_run_cmd brew update
    elif is_linux; then
        if sudo_available; then
            dry_run_cmd sudo apt-get update
        fi
    fi
}

# =============================================================================
# pkg_install — Install one or more packages
# =============================================================================
pkg_install() {
    local pkg
    local had_failure=false
    for pkg in "$@"; do
        if is_macos; then
            dry_run_cmd brew install "$pkg"
        elif is_linux; then
            if ! sudo_available; then
                record_missing_apt_package "$pkg"
                log_warn "Deferring ${pkg} to administrator (no sudo)"
                had_failure=true
                continue
            fi
            if command_exists apt-get; then
                dry_run_cmd sudo DEBIAN_FRONTEND=noninteractive apt-get install -y "$pkg"
            elif command_exists dnf; then
                dry_run_cmd sudo dnf install -y "$pkg"
            elif command_exists yum; then
                dry_run_cmd sudo yum install -y "$pkg"
            else
                log_error "No supported package manager found"
                return 1
            fi
        fi
    done
    [[ "$had_failure" == "true" ]] && return 1
    return 0
}

# =============================================================================
# pkg_install_cask — Install a macOS cask application
# =============================================================================
pkg_install_cask() {
    if ! is_macos; then
        log_warn "Cask install is only supported on macOS (skipping: $*)"
        return 0
    fi

    local pkg
    for pkg in "$@"; do
        dry_run_cmd brew install --cask "$pkg"
    done
}
