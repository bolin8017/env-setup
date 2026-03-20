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
