#!/usr/bin/env bash
# package.sh — Cross-platform package management abstraction
# Wraps brew/apt/dnf with a unified interface. Respects dry-run mode.

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
# pkg_update — Update package manager index
# =============================================================================
pkg_update() {
    if is_macos; then
        dry_run_cmd brew update
    elif is_linux; then
        dry_run_cmd sudo apt-get update
    fi
}

# =============================================================================
# pkg_install — Install one or more packages
# =============================================================================
pkg_install() {
    local pkg
    for pkg in "$@"; do
        if is_macos; then
            dry_run_cmd brew install "$pkg"
        elif is_linux; then
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
