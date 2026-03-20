#!/usr/bin/env bash
# 01-core.sh — Homebrew, Git, GitHub CLI, build tools
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

    if command_exists brew; then
        log_success "Homebrew already installed"
        return 0
    fi

    log_info "Installing Homebrew..."
    dry_run_cmd /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

    # Set up PATH for current session and write a shell fragment
    if [[ -f "/opt/homebrew/bin/brew" ]]; then
        eval "$(/opt/homebrew/bin/brew shellenv)"
    elif [[ -f "/usr/local/bin/brew" ]]; then
        eval "$(/usr/local/bin/brew shellenv)"
    fi

    # Write Homebrew fragment for future shells
    local fragment_dir="$HOME/.config/zsh/fragments"
    dry_run_mkdir "$fragment_dir"
    local fragment_file="$fragment_dir/41-homebrew.zsh"
    if [[ ! -f "$fragment_file" ]] || ! grep -q "brew shellenv" "$fragment_file" 2>/dev/null; then
        log_info "Writing Homebrew shell fragment: $fragment_file"
        dry_run_cmd bash -c "cat > '$fragment_file' << 'FRAGMENT'
eval \"\$(/opt/homebrew/bin/brew shellenv)\" 2>/dev/null || eval \"\$(/usr/local/bin/brew shellenv)\" 2>/dev/null
FRAGMENT"
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
            pkg_update
            dry_run_cmd sudo DEBIAN_FRONTEND=noninteractive apt-get install -y \
                build-essential "${missing[@]}"
            log_success "Build tools installed"
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
    fi

    if cfg_enabled "core.github_cli"; then
        _install_gh
    fi

    if cfg_enabled "core.build_tools"; then
        _install_build_tools
    fi
}
