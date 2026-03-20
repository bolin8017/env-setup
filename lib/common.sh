#!/usr/bin/env bash
# common.sh — Core utilities: logging, platform detection, shell helpers
# Sourced by all other scripts in the env-setup monorepo.

# Guard: only apply strict mode when run standalone
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    set -euo pipefail
fi

# Prevent double-sourcing
[[ -n "${_ENV_SETUP_COMMON_LOADED:-}" ]] && return 0
_ENV_SETUP_COMMON_LOADED=1

# =============================================================================
# Colors
# =============================================================================
RED=$'\033[0;31m'
GREEN=$'\033[0;32m'
YELLOW=$'\033[1;33m'
BLUE=$'\033[0;34m'
CYAN=$'\033[0;36m'
BOLD=$'\033[1m'
NC=$'\033[0m'

# =============================================================================
# Logging
# =============================================================================
LOG_DIR="${LOG_DIR:-$HOME/.env-setup}"
INSTALL_LOG="${INSTALL_LOG:-$LOG_DIR/install.log}"
ERROR_LOG="${ERROR_LOG:-$LOG_DIR/error.log}"

setup_logging() {
    mkdir -p "$LOG_DIR"
    touch "$INSTALL_LOG" "$ERROR_LOG"
}

# Internal: write to log file and stdout
_log() {
    local msg="$1"
    echo -e "$msg"
    echo -e "$msg" >> "$INSTALL_LOG"
}

log_info() {
    _log "${CYAN}[INFO]${NC} $1"
}

log_success() {
    _log "${GREEN}[OK]${NC} $1"
}

log_warn() {
    _log "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" | tee -a "$ERROR_LOG" >&2
}

print_header() {
    echo ""
    _log "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    _log "${BOLD}${BLUE}  $1${NC}"
    _log "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

# =============================================================================
# Platform detection
# =============================================================================
detect_os() {
    if [[ -n "${_CACHED_OS:-}" ]]; then echo "$_CACHED_OS"; return; fi
    case "$(uname -s)" in
        Darwin) _CACHED_OS="macos" ;;
        Linux)
            if grep -qi microsoft /proc/version 2>/dev/null || \
               grep -qi wsl /proc/version 2>/dev/null; then
                _CACHED_OS="wsl"
            else
                _CACHED_OS="linux"
            fi
            ;;
        *) _CACHED_OS="unknown" ;;
    esac
    echo "$_CACHED_OS"
}

detect_arch() {
    if [[ -n "${_CACHED_ARCH:-}" ]]; then echo "$_CACHED_ARCH"; return; fi
    case "$(uname -m)" in
        x86_64)  _CACHED_ARCH="amd64" ;;
        aarch64) _CACHED_ARCH="arm64" ;;
        arm64)   _CACHED_ARCH="arm64" ;;
        *)       _CACHED_ARCH="$(uname -m)" ;;
    esac
    echo "$_CACHED_ARCH"
}

is_macos() { [[ "$(detect_os)" == "macos" ]]; }
is_linux() { local os; os="$(detect_os)"; [[ "$os" == "linux" ]] || [[ "$os" == "wsl" ]]; }
is_wsl()   { [[ "$(detect_os)" == "wsl" ]]; }

# =============================================================================
# Shell detection
# =============================================================================
detect_shell() {
    if [[ -n "${ZSH_VERSION:-}" ]] || [[ "$SHELL" == */zsh ]]; then
        echo "zsh"
    elif [[ -n "${BASH_VERSION:-}" ]] || [[ "$SHELL" == */bash ]]; then
        echo "bash"
    else
        echo "unknown"
    fi
}

# Return path to the user's shell rc file
shell_rc_file() {
    case "$(detect_shell)" in
        zsh)  echo "$HOME/.zshrc" ;;
        bash) echo "$HOME/.bashrc" ;;
        *)    echo "$HOME/.profile" ;;
    esac
}

# =============================================================================
# Utility functions
# =============================================================================
command_exists() {
    command -v "$1" &>/dev/null
}

# Prompt user with yes/no. Respects AUTO_YES for non-interactive runs.
ask_yes_no() {
    local prompt="$1"
    local default="${2:-n}"

    if [[ "${AUTO_YES:-false}" == "true" ]]; then
        return 0
    fi

    local response
    while true; do
        if [[ "$default" == "y" ]]; then
            read -rp "$(echo -e "${CYAN}${prompt} [Y/n]: ${NC}")" response
            response="${response:-y}"
        else
            read -rp "$(echo -e "${CYAN}${prompt} [y/N]: ${NC}")" response
            response="${response:-n}"
        fi

        case "$response" in
            [Yy]*) return 0 ;;
            [Nn]*) return 1 ;;
            *) echo "Please answer yes or no." ;;
        esac
    done
}

# Idempotently add content to a shell config file
add_to_shell_config() {
    local content="$1"
    local config_file="${2:-$(shell_rc_file)}"

    touch "$config_file"

    local first_line
    first_line=$(echo "$content" | head -n 1)

    if ! grep -qF "$first_line" "$config_file" 2>/dev/null; then
        echo "$content" >> "$config_file"
        log_info "Added to $config_file"
    fi
}
