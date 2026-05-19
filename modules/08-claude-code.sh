#!/usr/bin/env bash
# 08-claude-code.sh — Install Claude Code CLI + ccstatusline integration
# Dependencies: lib/common.sh, lib/config.sh, lib/dryrun.sh

# =============================================================================
# _install_claude_native — Native installer (curl | bash), idempotent
# =============================================================================
_install_claude_native() {
    print_header "Claude Code"

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

# =============================================================================
# _deploy_ccstatusline_config — Copy template to ~/.config/ccstatusline/
# =============================================================================
_deploy_ccstatusline_config() {
    local src="${ENV_SETUP_DIR}/configs/ccstatusline/settings.json"
    local dest_dir="${HOME}/.config/ccstatusline"
    local dest="${dest_dir}/settings.json"

    dry_run_mkdir "$dest_dir"
    deploy_config "$src" "$dest" "ccstatusline settings.json"
}

# =============================================================================
# _merge_claude_statusline — jq-merge statusLine into ~/.claude/settings.json
# Idempotent: skips when .statusLine.command already matches. Mutating
# writes a timestamped .bak next to the file.
# =============================================================================
_merge_claude_statusline() {
    local settings="${HOME}/.claude/settings.json"
    local target_cmd="npx -y ccstatusline@latest"

    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_info "[DRY-RUN] Would merge statusLine into ${settings}"
        return 0
    fi

    # Case 1: file does not exist — write a minimal fresh one (no jq needed)
    if [[ ! -f "$settings" ]]; then
        dry_run_mkdir "$(dirname "$settings")"
        cat > "$settings" <<'JSON'
{
  "statusLine": {
    "type": "command",
    "command": "npx -y ccstatusline@latest",
    "padding": 0,
    "refreshInterval": 10
  }
}
JSON
        log_success "Created ${settings} with statusLine block"
        return 0
    fi

    # Case 2: jq missing — degrade gracefully
    if ! command_exists jq; then
        log_warn "jq not found — skipping ~/.claude/settings.json merge."
        log_warn "Add this block manually:"
        log_warn '  "statusLine": { "type": "command", "command": "npx -y ccstatusline@latest", "padding": 0, "refreshInterval": 10 }'
        return 0
    fi

    # Case 3: malformed JSON — refuse to guess
    if ! jq empty "$settings" 2>/dev/null; then
        log_error "${settings} is not valid JSON — skipping merge. Fix the file manually."
        return 0
    fi

    # Case 4: idempotent check
    local current_cmd
    current_cmd="$(jq -r '.statusLine.command // empty' "$settings" 2>/dev/null)" || true
    if [[ "$current_cmd" == "$target_cmd" ]]; then
        log_info "statusLine already configured — skipping merge"
        return 0
    fi

    # Case 5: mutate — backup, then atomic write
    local ts
    ts="$(date +%Y%m%d_%H%M%S)"
    local bak="${settings}.bak.${ts}"
    if ! cp -p "$settings" "$bak"; then
        log_error "Failed to create backup ${bak} — aborting merge"
        return 0
    fi
    log_info "Backed up existing settings.json to ${bak}"

    local tmp="${settings}.tmp.$$"
    if jq '.statusLine = {
              type: "command",
              command: "npx -y ccstatusline@latest",
              padding: 0,
              refreshInterval: 10
          }' "$settings" > "$tmp"; then
        if mv "$tmp" "$settings"; then
            log_success "Merged statusLine into ${settings}"
        else
            log_error "Failed to move ${tmp} into place — backup at ${bak}"
            rm -f "$tmp"
        fi
    else
        log_error "jq merge failed — original preserved, backup at ${bak}"
        rm -f "$tmp"
    fi
}

# =============================================================================
# _install_ccstatusline — Orchestrate the two ccstatusline-related steps
# =============================================================================
_install_ccstatusline() {
    if ! cfg_enabled "claude_code.ccstatusline.enabled"; then
        log_info "ccstatusline disabled in config — skipping"
        return 0
    fi

    print_header "ccstatusline"
    _deploy_ccstatusline_config
    _merge_claude_statusline
}

# =============================================================================
# install_claude_code — Main entry point (signature unchanged)
# =============================================================================
install_claude_code() {
    if ! cfg_enabled "claude_code.enabled"; then
        log_info "Claude Code disabled in config — skipping"
        return 0
    fi

    _install_claude_native
    _install_ccstatusline
}
