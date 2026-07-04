#!/usr/bin/env bash
# 03-python-tools.sh — Jupyter, Poetry (isolated uv tools)
# All lib/ files are sourced by setup.sh before this module runs.
# uv itself is installed by 02-languages (it is the Python manager). The
# uv-managed CPython is PEP 668 externally-managed, so tools must NOT be
# pip-installed into it — each gets its own uv-tool venv with executables
# exposed in ~/.local/bin.

# =============================================================================
# Jupyter Lab
# =============================================================================
_install_jupyter() {
    # jupyter-lab is the exposed entry point; bare `jupyter` only exists on
    # legacy (pip-based) installs — treat either as already-installed.
    if command_exists jupyter-lab || command_exists jupyter; then
        log_success "JupyterLab already installed"
        return 0
    fi

    log_info "Installing JupyterLab (uv tool)..."
    dry_run_cmd uv tool install jupyterlab
    verify_installed jupyter-lab "JupyterLab"
}

# =============================================================================
# Poetry
# =============================================================================
_install_poetry() {
    if command_exists poetry; then
        log_success "Poetry already installed"
        return 0
    fi

    log_info "Installing Poetry (uv tool)..."
    dry_run_cmd uv tool install poetry
    verify_installed poetry "Poetry"
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
}

# =============================================================================
# uninstall_python_tools — Reverse install_python_tools: jupyter / poetry / uv.
# All user-space (T); only brew-managed uv on macOS is system-level (P).
# =============================================================================
uninstall_python_tools() {
    print_header "Uninstall: Python Tools"

    if [[ "${KEEP_TOOLS:-false}" != "true" ]]; then
        # uv-tool venvs (post-migration installs); no-ops when absent. Must
        # run before uv itself is removed below.
        if command_exists uv; then
            dry_run_cmd uv tool uninstall jupyterlab 2>/dev/null || true
            dry_run_cmd uv tool uninstall poetry 2>/dev/null || true
        fi

        # Legacy pip-installed Jupyter (pre-uv-migration installs)
        if command_exists jupyter || command_exists pip3 || command_exists python3; then
            dry_run_cmd python3 -m pip uninstall -y jupyterlab notebook 2>/dev/null || true
            log_success "Removed Jupyter (jupyterlab, notebook)"
        fi

        # Poetry — legacy official-installer path, then sweep leftover paths
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
