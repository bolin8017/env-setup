#!/usr/bin/env bash
# 08-claude-code.sh — Install Claude Code CLI via native installer
# Dependencies: lib/common.sh, lib/config.sh, lib/dryrun.sh

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

    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_info "[DRY-RUN] Would run: curl -fsSL https://claude.ai/install.sh | bash"
        return 0
    fi

    local installer
    if ! installer="$(curl -fsSL https://claude.ai/install.sh)"; then
        log_error "Failed to download Claude Code installer"
        return 1
    fi

    if ! bash -c "$installer"; then
        log_error "Claude Code installer failed"
        return 1
    fi

    # Post-install verification
    # The installer places the binary at ~/.local/bin/claude
    export PATH="$HOME/.local/bin:$PATH"
    if command_exists claude; then
        log_success "Claude Code installed"
    else
        log_error "Claude Code installation completed but 'claude' not found in PATH"
        return 1
    fi
}
