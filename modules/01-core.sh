#!/usr/bin/env bash
# 01-core.sh — Homebrew, Git (+ two global defaults), GitHub CLI, build tools
# All lib/ files are sourced by setup.sh before this module runs.

# =============================================================================
# Homebrew (macOS only)
# =============================================================================
_install_homebrew() {
    print_header "Homebrew"

    if ! is_macos; then
        log_info "Skipping Homebrew (Linux uses apt)"
        return 0
    fi

    # Ensure brew PATH is set if already installed but not in PATH
    if [[ -f "/opt/homebrew/bin/brew" ]]; then
        eval "$(/opt/homebrew/bin/brew shellenv)"
    elif [[ -f "/usr/local/bin/brew" ]]; then
        eval "$(/usr/local/bin/brew shellenv)"
    fi

    # Write the Homebrew fragment before the already-installed early return:
    # a pre-installed brew (e.g. user-installed on Apple Silicon) still needs
    # shellenv in the env-setup-managed .zshrc, or new shells lose brew's PATH.
    write_generated_fragment "41-homebrew.zsh" << 'FRAGMENT'
eval "$(/opt/homebrew/bin/brew shellenv)" 2>/dev/null || eval "$(/usr/local/bin/brew shellenv)" 2>/dev/null
FRAGMENT

    if command_exists brew; then
        log_success "Homebrew already installed"
        return 0
    fi

    log_info "Installing Homebrew..."
    # Single quotes defer the curl to execution time: with "$(curl ...)" the
    # substitution runs BEFORE dry_run_cmd sees it — a dry run still hit the
    # network and dumped the whole installer into the log.
    dry_run_cmd bash -c 'curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh | /bin/bash'

    # Set up PATH for current session
    if [[ -f "/opt/homebrew/bin/brew" ]]; then
        eval "$(/opt/homebrew/bin/brew shellenv)"
    elif [[ -f "/usr/local/bin/brew" ]]; then
        eval "$(/usr/local/bin/brew shellenv)"
    fi

    if command_exists brew; then
        log_success "Homebrew installed"
    else
        log_error "Homebrew installation failed"
        return 1
    fi
}

# =============================================================================
# Git
# =============================================================================
_install_git() {
    print_header "Git"

    if command_exists git; then
        log_success "Git already installed ($(git --version))"
        return 0
    fi

    log_info "Installing Git..."
    pkg_install git
    log_success "Git installed"
}

# =============================================================================
# Git defaults — exactly two global settings, both reverted by uninstall:
#   1. a managed block in the global ignore file listing Claude Code's
#      per-machine settings.local.json (otherwise untracked noise in every repo)
#   2. rerere.enabled=true, only when the user has not set it either way
# No identity (user.name/email), aliases or pager are configured.
# =============================================================================
_GIT_IGNORE_BEGIN="# >>> env-setup managed >>>"
_GIT_IGNORE_END="# <<< env-setup managed <<<"
_GIT_IGNORE_ENTRY='**/.claude/settings.local.json'

# The file git consults for global excludes, in git's own lookup order
# (gitignore(5)): core.excludesFile when set, else $XDG_CONFIG_HOME/git/ignore,
# else ~/.config/git/ignore.
_git_global_ignore_path() {
    local configured=""
    configured="$(git config --global --get core.excludesFile 2>/dev/null || true)"
    if [[ -n "$configured" ]]; then
        # shellcheck disable=SC2088  # literal "~/" test: git hands back the unexpanded tilde
        [[ "$configured" == "~/"* ]] && configured="${HOME}/${configured#\~/}"
        printf '%s\n' "$configured"
        return 0
    fi
    printf '%s\n' "${XDG_CONFIG_HOME:-${HOME}/.config}/git/ignore"
}

_git_rerere_marker() { printf '%s\n' "${HOME}/.env-setup/.git-rerere-set"; }

_configure_git_defaults() {
    if ! command_exists git; then
        log_info "git not available yet — skipping git defaults"
        return 0
    fi

    # 1. global ignore block (idempotent: the begin marker is the receipt)
    local ignore_file
    ignore_file="$(_git_global_ignore_path)"
    if [[ -f "$ignore_file" ]] && grep -qF "$_GIT_IGNORE_BEGIN" "$ignore_file"; then
        log_info "git global ignore already carries the env-setup block"
    elif [[ "${DRY_RUN:-false}" == "true" ]]; then
        echo "[DRY-RUN] Would append the env-setup block to ${ignore_file}"
    else
        mkdir -p "$(dirname "$ignore_file")"
        # Start on a fresh line when the file lacks a trailing newline.
        if [[ -s "$ignore_file" && -n "$(tail -c1 "$ignore_file")" ]]; then
            printf '\n' >> "$ignore_file"
        fi
        printf '%s\n%s\n%s\n' "$_GIT_IGNORE_BEGIN" "$_GIT_IGNORE_ENTRY" "$_GIT_IGNORE_END" >> "$ignore_file"
        log_success "Added ${_GIT_IGNORE_ENTRY} to the git global ignore (${ignore_file})"
    fi

    # 2. rerere — leave any explicit user value (true or false) alone
    local marker
    marker="$(_git_rerere_marker)"
    if git config --global --get rerere.enabled >/dev/null 2>&1; then
        log_info "rerere.enabled already set — leaving it"
    else
        dry_run_cmd git config --global rerere.enabled true
        if [[ "${DRY_RUN:-false}" != "true" ]]; then
            mkdir -p "$(dirname "$marker")"
            : > "$marker"
            log_success "Enabled git rerere (recorded in ${marker} for uninstall)"
        fi
    fi
}

# Reverse _configure_git_defaults: strip the managed block; unset rerere only
# when the marker proves env-setup set it.
_unconfigure_git_defaults() {
    local ignore_file marker
    ignore_file="$(_git_global_ignore_path)"
    strip_block_from_file "$ignore_file" "$_GIT_IGNORE_BEGIN" "$_GIT_IGNORE_END"

    marker="$(_git_rerere_marker)"
    if [[ -f "$marker" ]]; then
        dry_run_cmd git config --global --unset rerere.enabled
        if [[ "${DRY_RUN:-false}" != "true" ]]; then
            rm -f "$marker"
            log_success "Disabled git rerere (env-setup had enabled it)"
        fi
    else
        log_info "rerere.enabled was not set by env-setup — leaving it"
    fi
}

# =============================================================================
# GitHub CLI
# =============================================================================
_install_gh() {
    print_header "GitHub CLI"

    if command_exists gh; then
        log_success "GitHub CLI already installed"
        return 0
    fi

    if is_macos; then
        log_info "Installing GitHub CLI..."
        pkg_install gh
    elif is_linux; then
        log_info "Installing GitHub CLI..."
        if sudo_available; then
            # GitHub CLI official install method for Linux
            # shellcheck disable=SC2016  # single quotes are intentional (deferred expansion)
            dry_run_cmd bash -c '
                (type -p wget >/dev/null || sudo apt-get install wget -y) \
                && sudo mkdir -p -m 755 /etc/apt/keyrings \
                && wget -qO- https://cli.github.com/packages/githubcli-archive-keyring.gpg \
                   | sudo tee /etc/apt/keyrings/githubcli-archive-keyring.gpg > /dev/null \
                && sudo chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg \
                && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
                   | sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null \
                && sudo apt-get update \
                && sudo apt-get install gh -y
            '
        else
            record_missing_apt_note "GitHub CLI (gh): follow https://github.com/cli/cli/blob/trunk/docs/install_linux.md"
            log_warn "GitHub CLI install deferred to administrator"
            return 0
        fi
    fi

    if [[ "${DRY_RUN:-false}" == "true" ]] || command_exists gh; then
        log_success "GitHub CLI installed (run 'gh auth login' to authenticate)"
    else
        log_error "GitHub CLI installation failed"
    fi
}

# =============================================================================
# Build tools
# =============================================================================
_install_build_tools() {
    print_header "Build Tools"

    if is_macos; then
        # Install Xcode Command Line Tools (includes gcc, make, etc.)
        if xcode-select -p &>/dev/null; then
            log_success "Xcode Command Line Tools already installed"
        else
            log_info "Installing Xcode Command Line Tools..."
            dry_run_cmd xcode-select --install
            log_info "Please complete the installation dialog, then re-run this script"
            return 1
        fi

        # Install additional build tools via Homebrew
        local tools=("gcc" "cmake" "make" "automake" "autoconf" "pkg-config")
        for tool in "${tools[@]}"; do
            if command_exists "$tool"; then
                log_success "  $tool already installed"
            else
                log_info "  Installing $tool..."
                pkg_install "$tool" || log_error "  $tool installation failed"
            fi
        done
    else
        # Linux: install build essentials via apt
        local build_pkgs=("gcc" "g++" "make" "cmake" "automake" "autoconf" "pkg-config")
        local missing=()
        for tool in "${build_pkgs[@]}"; do
            if command_exists "$tool"; then
                log_success "  [SKIP] $tool already installed"
            else
                missing+=("$tool")
            fi
        done

        if [[ ${#missing[@]} -gt 0 ]]; then
            log_info "Installing missing build tools: ${missing[*]}"
            if sudo_available; then
                pkg_update
                dry_run_cmd sudo DEBIAN_FRONTEND=noninteractive apt-get install -y \
                    build-essential "${missing[@]}"
                log_success "Build tools installed"
            else
                record_missing_apt_package build-essential "${missing[@]}"
                log_warn "Build tools install deferred to administrator"
            fi
        else
            log_success "All build tools already installed"
        fi
    fi
}

# =============================================================================
# Main entry point
# =============================================================================
install_core() {
    if cfg_enabled "core.homebrew"; then
        _install_homebrew
    fi

    if cfg_enabled "core.git"; then
        _install_git
        _configure_git_defaults
    fi

    if cfg_enabled "core.github_cli"; then
        _install_gh
    fi

    if cfg_enabled "core.build_tools"; then
        _install_build_tools
    fi
}

# =============================================================================
# uninstall_core — Reverse install_core (Homebrew fragment, git defaults;
# --purge: git/gh/build tools). The platform package manager itself is never
# auto-removed.
# =============================================================================
uninstall_core() {
    print_header "Uninstall: Core"

    # C — config layer
    remove_fragment "41-homebrew.zsh" "brew shellenv"
    _unconfigure_git_defaults

    # P — system packages
    if [[ "${PURGE:-false}" == "true" ]]; then
        log_warn "git and gh are widely depended on — removing them per --purge"
        pkg_remove gh git
        if is_linux && sudo_available && command_exists apt-get; then
            dry_run_cmd sudo DEBIAN_FRONTEND=noninteractive apt-get purge -y build-essential
            dry_run_cmd sudo rm -f /etc/apt/sources.list.d/github-cli.list \
                                   /etc/apt/keyrings/githubcli-archive-keyring.gpg
        fi
        if is_macos; then
            log_info "Homebrew is the package manager — not auto-removed. To remove manually:"
            # shellcheck disable=SC2016  # literal command shown to the user, not expanded
            log_info '  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/uninstall.sh)"'
        fi
    fi

    log_success "Core uninstall complete"
}
