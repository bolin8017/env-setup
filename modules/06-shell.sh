#!/usr/bin/env bash
# 06-shell.sh — Zsh, Oh My Zsh, Powerlevel10k, plugins, and shell configuration
# Rewritten by combining:
#   - shell-setup-automation/scripts/install_oh_my_zsh.sh
#   - shell-setup-automation/scripts/install_p10k.sh
#   - shell-setup-automation/scripts/install_plugins.sh (plugin install)
#   - shell-setup-automation/install.sh (config deploy + chsh flow)
#
# Dependencies: lib/common.sh, lib/config.sh, lib/dryrun.sh, lib/package.sh
# All sourced by setup.sh before this module runs.
# ENV_SETUP_DIR must be set to the repo root by setup.sh.

# =============================================================================
# 1. install_zsh — Install zsh if not present
# =============================================================================
install_zsh() {
    if ! cfg_enabled "shell.install_zsh"; then
        log_info "Skipping zsh install (disabled in config)"
        return 0
    fi

    if command_exists zsh; then
        log_success "zsh already installed ($(zsh --version 2>/dev/null || echo 'unknown version'))"
        return 0
    fi

    log_info "Installing zsh..."
    pkg_install zsh

    if command_exists zsh; then
        log_success "zsh installed"
    else
        log_error "zsh installation failed"
        return 1
    fi
}

# =============================================================================
# 2. install_oh_my_zsh — Unattended Oh My Zsh install
# =============================================================================
install_oh_my_zsh() {
    if ! cfg_enabled "shell.oh_my_zsh"; then
        log_info "Skipping Oh My Zsh (disabled in config)"
        return 0
    fi

    local omz_dir="${HOME}/.oh-my-zsh"

    if [[ -d "$omz_dir" ]]; then
        log_info "Oh My Zsh already installed, updating..."
        dry_run_cmd git -C "$omz_dir" pull --rebase --quiet 2>/dev/null || true
        log_success "Oh My Zsh updated"
        return 0
    fi

    log_info "Installing Oh My Zsh (unattended)..."
    dry_run_cmd env RUNZSH=no KEEP_ZSHRC=yes \
        sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended

    if [[ -d "$omz_dir" ]]; then
        log_success "Oh My Zsh installed"
    else
        log_error "Oh My Zsh installation failed"
        return 1
    fi
}

# =============================================================================
# 3. install_powerlevel10k — Clone or update the P10k theme
# =============================================================================
install_powerlevel10k() {
    if ! cfg_enabled "shell.powerlevel10k"; then
        log_info "Skipping Powerlevel10k (disabled in config)"
        return 0
    fi

    local zsh_custom="${ZSH_CUSTOM:-${HOME}/.oh-my-zsh/custom}"
    local p10k_dir="${zsh_custom}/themes/powerlevel10k"

    if [[ -d "$p10k_dir" ]]; then
        log_info "Powerlevel10k already installed, updating..."
        dry_run_cmd git -C "$p10k_dir" pull --quiet
        log_success "Powerlevel10k updated"
    else
        log_info "Cloning Powerlevel10k..."
        dry_run_cmd git clone --depth=1 \
            https://github.com/romkatv/powerlevel10k.git "$p10k_dir"
        log_success "Powerlevel10k installed"
    fi

    log_info "Tip: install a Nerd Font (MesloLGS NF recommended) for best experience"
}

# =============================================================================
# 4. install_zsh_plugins — Clone external plugins from config
# =============================================================================
install_zsh_plugins() {
    local zsh_custom="${ZSH_CUSTOM:-${HOME}/.oh-my-zsh/custom}"

    # Read plugin list into array first to avoid stdin conflicts with git
    local -a plugins=()
    local p
    while IFS= read -r p; do
        [[ -n "$p" ]] && plugins+=("$p")
    done < <(cfg_list "shell.plugins.external")

    local plugin
    for plugin in "${plugins[@]}"; do
        local plugin_dir="${zsh_custom}/plugins/${plugin}"
        local repo_url="https://github.com/zsh-users/${plugin}.git"

        if [[ -d "$plugin_dir" ]]; then
            log_info "${plugin} already installed, updating..."
            dry_run_cmd git -C "$plugin_dir" pull --quiet
            log_success "${plugin} updated"
        else
            log_info "Cloning ${plugin}..."
            dry_run_cmd git clone "$repo_url" "$plugin_dir"
            log_success "${plugin} installed"
        fi
    done
}

# =============================================================================
# 5. deploy_shell_config — Deploy .zshrc skeleton and fragments
# =============================================================================
deploy_shell_config() {
    local src_dir="${ENV_SETUP_DIR}/configs"
    local frag_dest="${HOME}/.config/zsh/fragments"
    local custom_dest="${HOME}/.config/zsh/custom"

    # Create target directories
    dry_run_mkdir "$frag_dest"
    dry_run_mkdir "$custom_dest"

    # --- .zshrc skeleton (sources fragments + custom) ---
    # shellcheck disable=SC2088  # tilde is intentional display label
    deploy_config "${src_dir}/zshrc.base" "${HOME}/.zshrc" "~/.zshrc"

    # --- All fragment files ---
    if [[ -d "${src_dir}/zshrc" ]]; then
        local frag
        for frag in "${src_dir}/zshrc"/*.zsh; do
            [[ -f "$frag" ]] || continue
            dry_run_cp "$frag" "${frag_dest}/$(basename "$frag")"
        done
        log_success "Deployed zsh fragments to ${frag_dest}/"
    fi

    # --- Aliases ---
    deploy_config "${ENV_SETUP_DIR}/configs/aliases.zsh" "${HOME}/.config/zsh/aliases.zsh" "aliases.zsh"

    # --- Powerlevel10k config ---
    # shellcheck disable=SC2088  # tilde is intentional display label
    deploy_config "${src_dir}/p10k/.p10k.zsh" "${HOME}/.p10k.zsh" "~/.p10k.zsh"
}

# =============================================================================
# 6. set_default_shell — chsh to zsh if not already default
# =============================================================================
set_default_shell() {
    if ! cfg_enabled "shell.set_default_shell"; then
        log_info "Skipping default shell change (disabled in config)"
        return 0
    fi

    if [[ "$SHELL" == */zsh ]]; then
        log_success "zsh is already the default shell"
        return 0
    fi

    local zsh_path
    zsh_path="$(command -v zsh)"

    if [[ -z "$zsh_path" ]]; then
        log_error "zsh not found in PATH, cannot set as default shell"
        return 1
    fi

    # Ensure zsh is listed in /etc/shells
    if ! grep -qF "$zsh_path" /etc/shells 2>/dev/null; then
        log_info "Adding ${zsh_path} to /etc/shells..."
        dry_run_cmd bash -c "echo '${zsh_path}' | sudo tee -a /etc/shells"
    fi

    log_info "Changing default shell to zsh..."
    dry_run_cmd chsh -s "$zsh_path"
    log_success "Default shell set to zsh (log out and back in to take effect)"
}

# =============================================================================
# install_shell — Main entry point
# =============================================================================
install_shell() {
    print_header "Shell (Zsh + Oh My Zsh + Powerlevel10k)"

    install_zsh
    install_oh_my_zsh
    install_powerlevel10k
    install_zsh_plugins
    deploy_shell_config
    set_default_shell

    log_success "Shell module complete"
}
