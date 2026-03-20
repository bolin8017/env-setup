#!/usr/bin/env bash
# 05-cli-tools.sh — Install modern CLI tools (fzf, ripgrep, bat, fd, eza, etc.)
# Merged from dev-env-setup/modules/05-cli-tools.sh and
# shell-setup-automation/scripts/install_plugins.sh (install_modern_tools).
#
# Dependencies: lib/common.sh, lib/config.sh, lib/dryrun.sh, lib/package.sh
# All sourced by setup.sh before this module runs.

# =============================================================================
# Tool registry — "config_key:brew_pkg:apt_pkg:check_cmd"
#
# config_key  — matches cli_tools.<key> in config.yaml
# brew_pkg    — Homebrew formula name
# apt_pkg     — apt package name (may differ from brew)
# check_cmd   — binary name to test with command_exists
# =============================================================================
readonly CLI_TOOLS=(
    "fzf:fzf:fzf:fzf"
    "ripgrep:ripgrep:ripgrep:rg"
    "bat:bat:bat:bat"
    "jq:jq:jq:jq"
    "fd:fd:fd-find:fd"
    "btop:btop:btop:btop"
    "tldr:tldr:tldr:tldr"
    "tree:tree:tree:tree"
    "httpie:httpie:httpie:http"
    "eza:eza:eza:eza"
    "zoxide:zoxide:zoxide:zoxide"
)

# =============================================================================
# Helpers
# =============================================================================

# On older Ubuntu, bat is installed as "batcat" and fd as "fdfind".
# Return 0 if the tool (or its alias) is already available.
_tool_available() {
    local check_cmd="$1"
    if command_exists "$check_cmd"; then
        return 0
    fi
    # Check well-known Linux alternative names
    case "$check_cmd" in
        bat)  command_exists batcat  && return 0 ;;
        fd)   command_exists fdfind  && return 0 ;;
    esac
    return 1
}

# Get the Ubuntu major version (empty on non-Ubuntu / macOS)
_ubuntu_version() {
    if [[ -f /etc/os-release ]]; then
        # shellcheck disable=SC1091
        . /etc/os-release
        if [[ "${ID:-}" == "ubuntu" ]]; then
            echo "${VERSION_ID%%.*}"
            return
        fi
    fi
    echo ""
}

# =============================================================================
# install_eza — Special handling: not in default apt repos on Ubuntu < 24.04
# Uses the gierens.de apt repository on older Ubuntu.
# =============================================================================
_install_eza() {
    if ! cfg_enabled "cli_tools.eza"; then
        return 0
    fi

    if command_exists eza; then
        log_success "eza already installed"
        return 0
    fi

    log_info "Installing eza..."

    if is_macos; then
        pkg_install eza
    elif is_linux; then
        local ubuntu_ver
        ubuntu_ver="$(_ubuntu_version)"

        if [[ -n "$ubuntu_ver" ]] && (( ubuntu_ver >= 24 )); then
            # Ubuntu 24.04+ has eza in the default repos
            pkg_install eza
        else
            # Older Ubuntu: add the gierens.de repository
            log_info "Adding eza apt repository (gierens.de)..."
            dry_run_cmd sudo mkdir -p /etc/apt/keyrings
            dry_run_cmd bash -c \
                'wget -qO- https://raw.githubusercontent.com/eza-community/eza/main/deb.asc | sudo gpg --dearmor -o /etc/apt/keyrings/gierens.gpg'
            dry_run_cmd bash -c \
                'echo "deb [signed-by=/etc/apt/keyrings/gierens.gpg] http://deb.gierens.de stable main" | sudo tee /etc/apt/sources.list.d/gierens.list'
            dry_run_cmd sudo chmod 644 /etc/apt/keyrings/gierens.gpg /etc/apt/sources.list.d/gierens.list
            dry_run_cmd sudo apt-get update
            pkg_install eza
        fi
    fi

    if [[ "${DRY_RUN:-false}" == "true" ]] || command_exists eza; then
        log_success "eza installed"
    else
        log_error "eza installation failed"
    fi
}

# =============================================================================
# install_zoxide — On older Ubuntu it may not be in apt; fall back to installer
# =============================================================================
_install_zoxide() {
    if ! cfg_enabled "cli_tools.zoxide"; then
        return 0
    fi

    if command_exists zoxide; then
        log_success "zoxide already installed"
        return 0
    fi

    log_info "Installing zoxide..."

    if is_macos; then
        pkg_install zoxide
    elif is_linux; then
        # Try apt first; fall back to the official install script
        if pkg_install zoxide 2>/dev/null; then
            : # success
        else
            log_info "zoxide not available via apt, using install script..."
            dry_run_cmd bash -c \
                'curl -sS https://raw.githubusercontent.com/ajeetdsouza/zoxide/main/install.sh | bash'
        fi
    fi

    if [[ "${DRY_RUN:-false}" == "true" ]] || command_exists zoxide; then
        log_success "zoxide installed"
    else
        log_error "zoxide installation failed"
    fi
}

# =============================================================================
# deploy_tool_configs — Copy CLI tool shell integrations
# =============================================================================
_deploy_tool_configs() {
    local src_dir="${ENV_SETUP_DIR}/configs/zshrc"
    local dest_dir="${HOME}/.config/zsh/fragments"

    if [[ ! -f "${src_dir}/50-tools.zsh" ]]; then
        log_warn "50-tools.zsh not found in ${src_dir}, skipping config deploy"
        return 0
    fi

    dry_run_mkdir "$dest_dir"
    dry_run_cp "${src_dir}/50-tools.zsh" "${dest_dir}/50-tools.zsh"
    log_success "Deployed 50-tools.zsh to ${dest_dir}/"
}

# =============================================================================
# install_cli_tools — Main entry point
# =============================================================================
install_cli_tools() {
    print_header "CLI Tools"

    # Iterate over the tool registry
    local entry cfg_key brew_pkg apt_pkg check_cmd
    for entry in "${CLI_TOOLS[@]}"; do
        IFS=':' read -r cfg_key brew_pkg apt_pkg check_cmd <<< "$entry"

        # Skip if disabled in config
        if ! cfg_enabled "cli_tools.${cfg_key}"; then
            log_info "Skipping ${cfg_key} (disabled in config)"
            continue
        fi

        # Skip if already installed (including Linux alias names)
        if _tool_available "$check_cmd"; then
            log_success "${cfg_key} already installed"
            continue
        fi

        log_info "Installing ${cfg_key}..."

        # Special cases handled by dedicated functions
        case "$cfg_key" in
            eza)
                _install_eza
                continue
                ;;
            zoxide)
                _install_zoxide
                continue
                ;;
        esac

        # Standard install path
        if is_macos; then
            pkg_install "$brew_pkg"
        elif is_linux; then
            pkg_install "$apt_pkg"
        fi

        if [[ "${DRY_RUN:-false}" == "true" ]] || _tool_available "$check_cmd"; then
            log_success "${cfg_key} installed"
        else
            log_error "${cfg_key} installation failed"
        fi
    done

    # Deploy shell integration config
    _deploy_tool_configs

    log_success "CLI tools module complete"
}
