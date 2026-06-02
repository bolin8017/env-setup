#!/usr/bin/env bash
# 03-python-tools.sh — Jupyter, Poetry, uv
# All lib/ files are sourced by setup.sh before this module runs.

# =============================================================================
# Jupyter Lab
# =============================================================================
_install_jupyter() {
    if command_exists jupyter; then
        log_success "Jupyter already installed"
        return 0
    fi

    log_info "Installing Jupyter Lab..."
    dry_run_cmd python3 -m pip install jupyterlab notebook
    log_success "Jupyter Lab installed"
}

# =============================================================================
# Poetry
# =============================================================================
_install_poetry() {
    if command_exists poetry; then
        log_success "Poetry already installed"
        return 0
    fi

    log_info "Installing Poetry..."
    dry_run_cmd bash -c 'curl -sSL https://install.python-poetry.org | python3 -'
    export PATH="$HOME/.local/bin:$PATH"
    log_success "Poetry installed"
}

# =============================================================================
# uv
# =============================================================================
_install_uv() {
    if command_exists uv; then
        log_success "uv already installed"
        return 0
    fi

    log_info "Installing uv..."
    if is_macos; then
        pkg_install uv
    else
        dry_run_cmd bash -c 'curl -LsSf https://astral.sh/uv/install.sh | sh'
        export PATH="$HOME/.local/bin:$PATH"
    fi
    log_success "uv installed"
}

# =============================================================================
# Main entry point
# =============================================================================
install_python_tools() {
    if ! cfg_enabled "languages.python.enabled"; then
        log_info "Skipping Python tools (Python is disabled)"
        return 0
    fi

    print_header "Python Tools"

    if cfg_enabled "python_tools.jupyter"; then
        _install_jupyter
    fi

    if cfg_enabled "python_tools.poetry"; then
        _install_poetry
    fi

    if cfg_enabled "python_tools.uv"; then
        _install_uv
    fi
}

# =============================================================================
# uninstall_python_tools — Reverse install_python_tools: jupyter / poetry / uv.
# All user-space (T); only brew-managed uv on macOS is system-level (P).
# =============================================================================
uninstall_python_tools() {
    print_header "Uninstall: Python Tools"

    if [[ "${KEEP_TOOLS:-false}" != "true" ]]; then
        # Jupyter
        if command_exists jupyter || command_exists pip3 || command_exists python3; then
            dry_run_cmd python3 -m pip uninstall -y jupyterlab notebook 2>/dev/null || true
            log_success "Removed Jupyter (jupyterlab, notebook)"
        fi

        # Poetry — official uninstaller, then sweep leftover paths
        if command_exists poetry; then
            dry_run_cmd bash -c 'curl -sSL https://install.python-poetry.org | python3 - --uninstall' || true
        fi
        dry_run_rm "$HOME/.local/bin/poetry" "$HOME/.local/share/pypoetry"

        # uv — self-uninstall, then sweep leftover paths
        if command_exists uv; then
            dry_run_cmd uv self uninstall 2>/dev/null || true
        fi
        dry_run_rm "$HOME/.local/bin/uv" "$HOME/.local/bin/uvx" \
                   "$HOME/.local/share/uv" "$HOME/.cache/uv"
    fi

    # P — macOS brew install path for uv
    if [[ "${PURGE:-false}" == "true" ]] && is_macos; then
        pkg_remove uv
    fi

    log_success "Python tools uninstall complete"
}
