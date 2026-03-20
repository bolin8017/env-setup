#!/usr/bin/env bash
# 08-claude-code.sh — Install Claude Code CLI via native installer
# Dependencies: lib/common.sh, lib/config.sh

install_claude_code() {
    if ! cfg_enabled "claude_code.enabled"; then
        log_info "Claude Code disabled in config — skipping"
        return 0
    fi

    if command_exists claude; then
        log_success "Claude Code already installed"
        return 0
    fi

    log_info "Installing Claude Code via native installer..."

    # dry_run_cmd cannot be used here because installation is a two-step
    # process (download then execute) and we need to validate the download
    # before running it. Show the equivalent piped command for clarity.
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_info "[DRY-RUN] Would run: curl -fsSL https://claude.ai/install.sh | bash"
        return 0
    fi

    local installer
    if ! installer="$(curl -fsSL https://claude.ai/install.sh)"; then
        log_error "Failed to download Claude Code installer"
        return 1
    fi

    if [[ -z "$installer" ]]; then
        log_error "Claude Code installer script is empty — download may have been intercepted"
        return 1
    fi

    local install_output
    if ! install_output="$(bash -c "$installer" 2>&1)"; then
        log_error "Claude Code installer failed:"
        log_error "$install_output"
        return 1
    fi

    # Post-install verification
    # Ensure ~/.local/bin is on PATH for the command_exists check below
    export PATH="$HOME/.local/bin:$PATH"
    if command_exists claude; then
        log_success "Claude Code installed"
    else
        log_error "Claude Code installation completed but 'claude' not found in PATH"
        return 1
    fi
}
