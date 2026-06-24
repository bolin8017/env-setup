#!/usr/bin/env bash
# 02-languages.sh — nvm/Node.js, pyenv/Python, Conda
# All lib/ files are sourced by setup.sh before this module runs.

# =============================================================================
# nvm & Node.js
# =============================================================================
_install_nvm() {
    print_header "nvm & Node.js"

    # Setup NVM environment
    export NVM_DIR="$HOME/.nvm"

    if [[ -d "$HOME/.nvm" ]]; then
        log_success "nvm already installed"
    else
        log_info "Installing nvm..."
        dry_run_cmd bash -c 'curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh | bash'
    fi

    # Write nvm fragment for future shells
    local fragment_dir="$HOME/.config/zsh/fragments"
    dry_run_mkdir "$fragment_dir"
    local fragment_file="$fragment_dir/16-nvm.zsh"
    if [[ ! -f "$fragment_file" ]] || ! grep -q "NVM_DIR" "$fragment_file" 2>/dev/null; then
        log_info "Writing nvm shell fragment: $fragment_file"
        # Sourcing nvm.sh eagerly runs nvm's auto-use on every shell start
        # (~0.4s, often the single biggest startup cost). Avoid that, but still
        # put the default Node's bin on PATH eagerly (~0ms) so node/npm/npx are
        # real binaries — a lazy shell-function node is invisible to execvp, so
        # non-interactive children (Claude Code MCP servers, scripts) can't find
        # it. The `nvm` command itself stays lazy: rarely used interactively,
        # and sourcing nvm.sh is the slow part.
        dry_run_cmd bash -c "cat > '$fragment_file' << 'FRAGMENT'
export NVM_DIR=\"\$HOME/.nvm\"
if [ -s \"\$NVM_DIR/nvm.sh\" ]; then
  _nvm_bin=\"\$(command find \"\$NVM_DIR/versions/node\" -maxdepth 2 -type d -name bin 2>/dev/null | sort -V | tail -1)\"
  if [ -n \"\$_nvm_bin\" ]; then
    case \":\$PATH:\" in
      *\":\$_nvm_bin:\"*) ;;
      *) PATH=\"\$_nvm_bin:\$PATH\" ;;
    esac
  fi
  unset _nvm_bin
  _envsetup_load_nvm() {
    unset -f nvm _envsetup_load_nvm
    \\. \"\$NVM_DIR/nvm.sh\"
    [ -s \"\$NVM_DIR/bash_completion\" ] && \\. \"\$NVM_DIR/bash_completion\"
  }
  nvm() { _envsetup_load_nvm; nvm \"\$@\"; }
fi
FRAGMENT"
    fi

    # nvm.sh and nvm commands use uninitialized variables internally;
    # disable nounset for the entire nvm block to prevent crashes.
    set +u

    # Load nvm for current session
    [[ -s "$NVM_DIR/nvm.sh" ]] && \. "$NVM_DIR/nvm.sh"

    # Install Node.js at requested version
    local node_version
    node_version="$(cfg_get "languages.node.version")"
    node_version="${node_version:-lts}"

    if [[ "$node_version" == "lts" ]]; then
        if command_exists node; then
            log_success "Node.js $(node --version) already installed (requested: lts, skipping)"
        else
            log_info "Installing Node.js (lts)..."
            dry_run_cmd nvm install --lts
            dry_run_cmd nvm use --lts
            command_exists node && log_success "Node.js $(node --version) installed"
        fi
    else
        if nvm ls "$node_version" &>/dev/null; then
            local installed_ver
            installed_ver="$(nvm ls "$node_version" --no-colors 2>/dev/null | grep -oE 'v[0-9]+\.[0-9]+\.[0-9]+' | head -1)"
            log_success "Node.js ${installed_ver:-$node_version} already installed (requested: $node_version, skipping)"
            dry_run_cmd nvm use "$node_version"
        else
            log_info "Installing Node.js ${node_version}..."
            dry_run_cmd nvm install "$node_version"
            dry_run_cmd nvm use "$node_version"
            command_exists node && log_success "Node.js $(node --version) installed"
        fi
    fi

    set -u
}

# =============================================================================
# pyenv & Python
# =============================================================================
_install_pyenv() {
    print_header "pyenv & Python"

    # Setup pyenv environment
    export PYENV_ROOT="$HOME/.pyenv"
    export PATH="$PYENV_ROOT/bin:$PATH"

    if command_exists pyenv; then
        log_success "pyenv already installed"
    else
        log_info "Installing pyenv..."
        if is_macos; then
            pkg_install pyenv pyenv-virtualenv
        elif is_linux; then
            # Install pyenv build dependencies (apt — needs sudo)
            if sudo_available; then
                pkg_update
                dry_run_cmd sudo DEBIAN_FRONTEND=noninteractive apt-get install -y \
                    libssl-dev zlib1g-dev libbz2-dev libreadline-dev libsqlite3-dev \
                    libncursesw5-dev xz-utils tk-dev libxml2-dev libxmlsec1-dev \
                    libffi-dev liblzma-dev
            else
                record_missing_apt_package \
                    libssl-dev zlib1g-dev libbz2-dev libreadline-dev libsqlite3-dev \
                    libncursesw5-dev xz-utils tk-dev libxml2-dev libxmlsec1-dev \
                    libffi-dev liblzma-dev
                log_warn "pyenv build dependencies deferred to administrator (pyenv itself will still install but Python builds will fail)"
            fi
            # pyenv itself installs into $HOME — no sudo required
            dry_run_cmd bash -c 'curl https://pyenv.run | bash'
        fi
    fi

    # Write pyenv fragment for future shells
    local fragment_dir="$HOME/.config/zsh/fragments"
    dry_run_mkdir "$fragment_dir"
    local fragment_file="$fragment_dir/15-pyenv.zsh"
    if [[ ! -f "$fragment_file" ]] || ! grep -q "PYENV_ROOT" "$fragment_file" 2>/dev/null; then
        log_info "Writing pyenv shell fragment: $fragment_file"
        # --no-rehash: skip the implicit 'pyenv rehash' that BOTH 'pyenv init
        # --path' and 'pyenv init -' emit on every shell start. An interrupted
        # rehash leaves a stale ~/.pyenv/shims/.pyenv-shim lock; subsequent
        # rehashes then block ~60s each waiting for it, stalling shell startup
        # by minutes. Shims are still refreshed by 'pyenv install' and a manual
        # 'pyenv rehash' when needed.
        dry_run_cmd bash -c "cat > '$fragment_file' << 'FRAGMENT'
export PYENV_ROOT=\"\$HOME/.pyenv\"
[[ -d \"\$PYENV_ROOT/bin\" ]] && export PATH=\"\$PYENV_ROOT/bin:\$PATH\"
eval \"\$(pyenv init --path --no-rehash)\" 2>/dev/null
eval \"\$(pyenv init - --no-rehash)\" 2>/dev/null
FRAGMENT"
    fi

    # Ensure pyenv is in PATH for current session (disable nounset for pyenv init).
    # --no-rehash matches the generated fragment; 'pyenv install' below rehashes.
    export PATH="$PYENV_ROOT/bin:$PYENV_ROOT/shims:$PATH"
    set +u
    eval "$(pyenv init --path --no-rehash)" 2>/dev/null || true
    eval "$(pyenv init - --no-rehash)" 2>/dev/null || true
    set -u

    # Install Python version specified in config
    local python_version
    python_version="$(cfg_get "languages.python.version")"
    python_version="${python_version:-3.12}"

    if ! pyenv versions 2>/dev/null | grep -q "$python_version"; then
        log_info "Installing Python $python_version..."
        dry_run_cmd pyenv install "$python_version"
        dry_run_cmd pyenv global "$python_version"
        log_success "Python $python_version set as global"
    else
        log_success "Python $python_version already installed"
        pyenv global "$python_version" 2>/dev/null || true
    fi
}

# =============================================================================
# Conda
# =============================================================================
_install_conda() {
    print_header "Conda"

    # Source conda if already installed but not in PATH (disable nounset for conda init)
    local brew_prefix
    brew_prefix="$(brew --prefix 2>/dev/null || echo /opt/homebrew)"

    set +u
    if [[ -f "$HOME/miniconda3/etc/profile.d/conda.sh" ]]; then
        . "$HOME/miniconda3/etc/profile.d/conda.sh"
    elif is_macos; then
        if [[ -f "$brew_prefix/Caskroom/miniconda/base/etc/profile.d/conda.sh" ]]; then
            . "$brew_prefix/Caskroom/miniconda/base/etc/profile.d/conda.sh"
        fi
    fi

    set -u

    if command_exists conda; then
        log_success "Conda already installed"
        return 0
    fi

    log_info "Installing Miniconda..."

    if is_macos; then
        dry_run_cmd brew install --cask miniconda
        local conda_path="$brew_prefix/Caskroom/miniconda/base"
        if [[ -f "$conda_path/etc/profile.d/conda.sh" ]]; then
            . "$conda_path/etc/profile.d/conda.sh"
            dry_run_cmd conda init "$(basename "$SHELL")"
        fi
    elif is_linux; then
        local arch
        arch="$(uname -m)"
        local miniconda_installer="/tmp/miniconda.sh"
        dry_run_cmd curl -fsSL "https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-${arch}.sh" -o "$miniconda_installer"
        dry_run_cmd bash "$miniconda_installer" -b -p "$HOME/miniconda3"
        dry_run_cmd rm -f "$miniconda_installer"

        if [[ -f "$HOME/miniconda3/etc/profile.d/conda.sh" ]]; then
            . "$HOME/miniconda3/etc/profile.d/conda.sh"
            dry_run_cmd conda init "$(basename "$SHELL")"
        fi
    fi

    # Write conda fragment for future shells
    local fragment_dir="$HOME/.config/zsh/fragments"
    dry_run_mkdir "$fragment_dir"
    local fragment_file="$fragment_dir/17-conda.zsh"
    if [[ ! -f "$fragment_file" ]] || ! grep -q "conda" "$fragment_file" 2>/dev/null; then
        log_info "Writing conda shell fragment: $fragment_file"
        dry_run_cmd bash -c "cat > '$fragment_file' << 'FRAGMENT'
# Conda (auto-generated by env-setup)
if [ -f \"\$HOME/miniconda3/etc/profile.d/conda.sh\" ]; then
    . \"\$HOME/miniconda3/etc/profile.d/conda.sh\"
elif [ -f \"/opt/homebrew/Caskroom/miniconda/base/etc/profile.d/conda.sh\" ]; then
    . \"/opt/homebrew/Caskroom/miniconda/base/etc/profile.d/conda.sh\"
elif [ -f \"/usr/local/Caskroom/miniconda/base/etc/profile.d/conda.sh\" ]; then
    . \"/usr/local/Caskroom/miniconda/base/etc/profile.d/conda.sh\"
else
    export PATH=\"\$HOME/miniconda3/bin:\$PATH\"
fi
FRAGMENT"
    fi

    log_success "Conda installed (restart terminal to activate)"
}

# =============================================================================
# Main entry point
# =============================================================================
install_languages() {
    if cfg_enabled "languages.node.enabled"; then
        _install_nvm
    fi

    if cfg_enabled "languages.python.enabled"; then
        _install_pyenv
    fi

    if cfg_enabled "languages.conda.enabled"; then
        _install_conda
    fi
}

# =============================================================================
# uninstall_languages — Reverse install_languages: remove the generated shell
# fragments + conda init block (C), the tool trees ~/.nvm ~/.pyenv ~/miniconda3
# (T), and brew-managed pyenv/miniconda on macOS (P).
# =============================================================================
uninstall_languages() {
    print_header "Uninstall: Languages"

    # C — auto-generated fragments this module wrote
    remove_fragment "15-pyenv.zsh" "PYENV_ROOT"
    remove_fragment "16-nvm.zsh" "NVM_DIR"
    remove_fragment "17-conda.zsh" "conda"

    # C — conda init block in shared rc files
    if command_exists conda; then
        set +u
        dry_run_cmd conda init --reverse --all 2>/dev/null || true
        set -u
    else
        strip_block_from_file "$HOME/.bashrc" "# >>> conda initialize >>>" "# <<< conda initialize <<<"
        strip_block_from_file "$HOME/.zshrc"  "# >>> conda initialize >>>" "# <<< conda initialize <<<"
    fi

    # T — user-space tool trees
    if [[ "${KEEP_TOOLS:-false}" != "true" ]]; then
        remove_managed_dir "$HOME/.nvm" "nvm"
        remove_managed_dir "$HOME/.pyenv" "pyenv"
        remove_managed_dir "$HOME/miniconda3" "Miniconda"
    fi

    # P — macOS brew-managed language tooling
    if [[ "${PURGE:-false}" == "true" ]] && is_macos; then
        pkg_remove pyenv pyenv-virtualenv
        pkg_remove_cask miniconda
    fi

    log_success "Languages uninstall complete"
}
