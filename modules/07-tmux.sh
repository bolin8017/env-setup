#!/usr/bin/env bash
# 07-tmux.sh — tmux installation, TPM, config deployment, plugin install
# Rewritten from tmux-config/install.sh.
# Simplified: only apt (Ubuntu/WSL) + brew (macOS). No dnf/yum/pacman/zypper/apk.
#
# Dependencies: lib/common.sh, lib/config.sh, lib/dryrun.sh, lib/package.sh
# All sourced by setup.sh before this module runs.
# ENV_SETUP_DIR must be set to the repo root by setup.sh.

# =============================================================================
# 1. install_tmux — Install tmux binary if not present
# =============================================================================
_install_tmux_bin() {
    if command_exists tmux; then
        log_success "tmux already installed ($(tmux -V 2>/dev/null || echo 'unknown version'))"
        return 0
    fi

    log_info "Installing tmux..."
    pkg_install tmux

    if command_exists tmux; then
        log_success "tmux installed"
    else
        log_error "tmux installation failed"
        return 1
    fi
}

# =============================================================================
# 2. install_clipboard_tool — Platform-specific clipboard integration
#    Linux/WSL: xclip    macOS: pbcopy/pbpaste (native)
# =============================================================================
_install_clipboard_tool() {
    if is_macos; then
        # Modern tmux (3.2+) doesn't need reattach-to-user-namespace
        # pbcopy/pbpaste work natively
        log_info "macOS clipboard: pbcopy/pbpaste (native, no extra tools needed)"
    elif is_linux; then
        if ! command_exists xclip; then
            log_info "Installing xclip..."
            pkg_install xclip
            if [[ "${DRY_RUN:-false}" == "true" ]] || command_exists xclip; then
                log_success "xclip installed"
            else
                log_warn "xclip installation failed (clipboard integration may not work)"
            fi
        else
            log_success "xclip already installed"
        fi
    fi
}

# =============================================================================
# 3. install_tpm — Clone tmux-plugins/tpm
# =============================================================================
_install_tpm() {
    if ! cfg_enabled "tmux.tpm"; then
        log_info "Skipping TPM (disabled in config)"
        return 0
    fi

    local tpm_dir="${HOME}/.tmux/plugins/tpm"

    if [[ -d "$tpm_dir" ]]; then
        log_info "TPM already installed, updating..."
        dry_run_cmd git -C "$tpm_dir" pull --quiet
        log_success "TPM updated"
    else
        log_info "Installing Tmux Plugin Manager (TPM)..."
        dry_run_mkdir "${HOME}/.tmux/plugins"
        dry_run_cmd git clone https://github.com/tmux-plugins/tpm "$tpm_dir"
        if [[ -d "$tpm_dir" ]]; then
            log_success "TPM installed"
        else
            log_error "TPM installation failed"
            return 1
        fi
    fi
}

# =============================================================================
# 4. deploy_tmux_config — Copy tmux configuration files
# =============================================================================
_deploy_tmux_config() {
    local src_dir="${ENV_SETUP_DIR}/configs/tmux"

    if [[ ! -d "$src_dir" ]]; then
        log_warn "Tmux config directory not found: ${src_dir}"
        return 0
    fi

    dry_run_mkdir "${HOME}/.tmux"

    # Main tmux.conf
    # shellcheck disable=SC2088  # tilde is intentional display label
    deploy_config "${src_dir}/tmux.conf" "${HOME}/.tmux.conf" "~/.tmux.conf"

    # macOS-specific: append source-file directive so the main config
    # conditionally loads the macOS overrides.
    if is_macos && [[ -f "${src_dir}/tmux.macos.conf" ]]; then
        deploy_config "${src_dir}/tmux.macos.conf" "${HOME}/.tmux/tmux.macos.conf" "tmux.macos.conf"

        # Append source-if-exists for the macOS config (idempotent)
        local source_line='if-shell "uname | grep -q Darwin" "source-file ~/.tmux/tmux.macos.conf"'
        if ! grep -qF "tmux.macos.conf" "${HOME}/.tmux.conf" 2>/dev/null; then
            if [[ "${DRY_RUN:-false}" == "true" ]]; then
                echo "[DRY-RUN] Would append macOS source-file to ~/.tmux.conf"
            else
                {
                    echo ""
                    echo "# macOS-specific overrides"
                    echo "$source_line"
                } >> "${HOME}/.tmux.conf"
            fi
        fi
    fi

    # Dev layout
    deploy_config "${src_dir}/dev-layout.conf" "${HOME}/.tmux/dev-layout.conf" "dev-layout.conf"
}

# =============================================================================
# 5. install_tmux_plugins — Run TPM install command (headless)
# =============================================================================
_install_tmux_plugins() {
    if ! cfg_enabled "tmux.auto_install_plugins"; then
        log_info "Skipping automatic plugin install (disabled in config)"
        return 0
    fi

    local tpm_install="${HOME}/.tmux/plugins/tpm/bin/install_plugins"

    if [[ ! -x "$tpm_install" ]]; then
        log_warn "TPM install script not found, skipping plugin install"
        return 0
    fi

    log_info "Installing tmux plugins via TPM..."

    if command_exists tmux; then
        if tmux list-sessions &>/dev/null 2>&1; then
            # tmux server is already running
            dry_run_cmd "$tpm_install"
        else
            # Start a temporary tmux session for plugin installation
            dry_run_cmd tmux start-server
            dry_run_cmd tmux new-session -d -s _tpm_install
            dry_run_cmd "$tpm_install"
            dry_run_cmd tmux kill-session -t _tpm_install 2>/dev/null || true
        fi
        log_success "tmux plugins installed"
    else
        log_warn "tmux not found, cannot install plugins"
    fi
}

# =============================================================================
# install_tmux — Main entry point
# =============================================================================
install_tmux() {
    print_header "tmux"

    if ! cfg_enabled "tmux.enabled"; then
        log_info "Skipping tmux module (disabled in config)"
        return 0
    fi

    _install_tmux_bin
    _install_clipboard_tool
    _install_tpm
    _deploy_tmux_config
    _install_tmux_plugins

    log_success "tmux module complete"
}
