#!/usr/bin/env bash
# 02-languages.sh — nvm/Node.js, uv/Python, Conda
# All lib/ files are sourced by setup.sh before this module runs.

# =============================================================================
# nvm & Node.js
# =============================================================================
_install_nvm() {
    print_header "nvm & Node.js"

    # Setup NVM environment
    export NVM_DIR="$HOME/.nvm"

    # Probe the loader, not just the directory: an interrupted install leaves
    # ~/.nvm without nvm.sh, and a bare -d check then skips the repair forever
    # (same class as the Oh My Zsh half-install fix).
    if [[ -s "$HOME/.nvm/nvm.sh" ]]; then
        log_success "nvm already installed"
    else
        if [[ -d "$HOME/.nvm" ]]; then
            log_warn "Incomplete nvm install detected; removing and reinstalling..."
            dry_run_rm "$HOME/.nvm"
        fi
        log_info "Installing nvm..."
        dry_run_cmd bash -c 'curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh | bash'
    fi

    # Write nvm fragment for future shells (content-compared, so fixes reach
    # already-provisioned machines).
    # Sourcing nvm.sh eagerly runs nvm's auto-use on every shell start
    # (~0.4s, often the single biggest startup cost). Avoid that, but still
    # put the default Node's bin on PATH eagerly (~0ms) so node/npm/npx are
    # real binaries — a lazy shell-function node is invisible to execvp, so
    # non-interactive children (Claude Code MCP servers, scripts) can't find
    # it. The `nvm` command itself stays lazy: rarely used interactively,
    # and sourcing nvm.sh is the slow part.
    write_generated_fragment "16-nvm.zsh" << 'FRAGMENT'
export NVM_DIR="$HOME/.nvm"
if [ -s "$NVM_DIR/nvm.sh" ]; then
  _nvm_bin="$(command find "$NVM_DIR/versions/node" -maxdepth 2 -type d -name bin 2>/dev/null | sort -V | tail -1)"
  if [ -n "$_nvm_bin" ]; then
    case ":$PATH:" in
      *":$_nvm_bin:"*) ;;
      *) PATH="$_nvm_bin:$PATH" ;;
    esac
  fi
  unset _nvm_bin
  _envsetup_load_nvm() {
    unset -f nvm _envsetup_load_nvm
    \. "$NVM_DIR/nvm.sh"
    [ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"
  }
  nvm() { _envsetup_load_nvm; nvm "$@"; }
fi
FRAGMENT

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
# uv & Python
# =============================================================================
_install_uv_python() {
    print_header "uv & Python"

    # uv is the Python manager: prebuilt standalone CPython, so no apt build
    # deps and no compile step. It may already be present from a
    # pre-migration install (03-python-tools ships it as a pip replacement).
    if command_exists uv; then
        log_success "uv already installed"
    else
        log_info "Installing uv..."
        if is_macos; then
            pkg_install uv
        else
            # Installs into ~/.local/bin — no sudo required.
            dry_run_cmd bash -c 'curl -LsSf https://astral.sh/uv/install.sh | sh'
        fi
    fi

    # uv and its managed-python shims land in ~/.local/bin; the static
    # fragment 40-env.zsh already puts that on PATH for future shells, so
    # no generated fragment is needed — only the current session.
    export PATH="$HOME/.local/bin:$PATH"

    local python_version
    python_version="$(cfg_get "languages.python.version")"
    python_version="${python_version:-3.12}"

    # uv resolves "3.12" to its newest patch itself, and re-running against
    # an installed version is a fast no-op. --default (uv preview feature)
    # adds the bare python/python3 shims — the moral equivalent of the old
    # `pyenv global`.
    log_info "Installing Python $python_version (uv-managed)..."
    dry_run_cmd uv python install "$python_version" --default
    log_success "Python $python_version set as the default python"

    # Machines provisioned before the uv migration still carry the generated
    # 15-pyenv.zsh fragment, which re-injects ~/.pyenv/shims into every new
    # shell — pip then resolves into the dead pyenv tree. Drop the fragment
    # (marker-guarded like remove_fragment); the ~/.pyenv tree itself stays
    # until uninstall.
    local legacy_frag="$HOME/.config/zsh/fragments/15-pyenv.zsh"
    if [[ -f "$legacy_frag" ]] && grep -qF 'PYENV_ROOT' "$legacy_frag"; then
        dry_run_rm "$legacy_frag"
        log_success "Removed legacy pyenv fragment (pre-uv provisioning)"
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

    # Write conda fragment for future shells (content-compared, so fixes reach
    # already-provisioned machines).
    write_generated_fragment "17-conda.zsh" << 'FRAGMENT'
# Conda (auto-generated by env-setup)
if [ -f "$HOME/miniconda3/etc/profile.d/conda.sh" ]; then
    . "$HOME/miniconda3/etc/profile.d/conda.sh"
elif [ -f "/opt/homebrew/Caskroom/miniconda/base/etc/profile.d/conda.sh" ]; then
    . "/opt/homebrew/Caskroom/miniconda/base/etc/profile.d/conda.sh"
elif [ -f "/usr/local/Caskroom/miniconda/base/etc/profile.d/conda.sh" ]; then
    . "/usr/local/Caskroom/miniconda/base/etc/profile.d/conda.sh"
else
    export PATH="$HOME/miniconda3/bin:$PATH"
fi
FRAGMENT

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
        _install_uv_python
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

    # C — auto-generated fragments this module wrote (15-pyenv.zsh is legacy:
    # written by pre-uv-migration installs only)
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

        # uv-managed CPython. 03-python-tools tears down uv itself (teardown
        # runs 09→01), so by now `uv python dir` may be unaskable — fall back
        # to uv's default location. The bare python/python3[.X] shims in
        # ~/.local/bin are symlinks into that tree; sweep them too or they
        # dangle once the tree goes.
        local uv_python_dir="$HOME/.local/share/uv/python"
        if command_exists uv; then
            uv_python_dir="$(uv python dir 2>/dev/null || echo "$uv_python_dir")"
        fi
        remove_managed_dir "$uv_python_dir" "uv-managed Python"
        local shim
        for shim in "$HOME/.local/bin/python" "$HOME/.local/bin/python3" "$HOME/.local/bin"/python3.*; do
            [[ -L "$shim" ]] || continue
            case "$(readlink "$shim")" in
                *uv/python/*) dry_run_rm "$shim" ;;
            esac
        done

        remove_managed_dir "$HOME/.pyenv" "pyenv"   # legacy (pre-uv installs)
        remove_managed_dir "$HOME/miniconda3" "Miniconda"
    fi

    # P — macOS brew-managed language tooling (pyenv formulas are legacy:
    # only pre-uv-migration installs put them there; uv itself is 03's)
    if [[ "${PURGE:-false}" == "true" ]] && is_macos; then
        pkg_remove pyenv pyenv-virtualenv
        pkg_remove_cask miniconda
    fi

    log_success "Languages uninstall complete"
}
