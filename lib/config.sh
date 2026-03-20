#!/usr/bin/env bash
# config.sh — Load config.yaml and expose CFG_* variables
# Supports CLI arg, local file, or built-in default path.
# Applies backward-compatible environment variable overrides.

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    set -euo pipefail
fi

[[ -n "${_ENV_SETUP_CONFIG_LOADED:-}" ]] && return 0
_ENV_SETUP_CONFIG_LOADED=1

# Resolve lib directory and source dependencies
_CONFIG_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${_CONFIG_LIB_DIR}/common.sh"
# shellcheck source=lib/yaml.sh
source "${_CONFIG_LIB_DIR}/yaml.sh"

# =============================================================================
# Locate config file
# =============================================================================
_find_config_file() {
    local config_file="${1:-}"

    # 1. Explicit CLI argument
    if [[ -n "$config_file" ]] && [[ -f "$config_file" ]]; then
        echo "$config_file"
        return 0
    fi

    # 2. ./config.yaml in project root
    local project_root
    project_root="$(cd "${_CONFIG_LIB_DIR}/.." && pwd)"
    if [[ -f "${project_root}/config.yaml" ]]; then
        echo "${project_root}/config.yaml"
        return 0
    fi

    log_error "No config file found (searched: CLI path, ${project_root}/config.yaml)"
    return 1
}

# =============================================================================
# load_config — Parse YAML and apply env overrides
# Usage: load_config [path/to/config.yaml]
# =============================================================================
load_config() {
    local config_file
    config_file="$(_find_config_file "${1:-}")"

    log_info "Loading config from: $config_file"

    # Parse YAML into CFG_* variables
    local parsed
    parsed="$(yaml_parse "$config_file")" || {
        log_error "Failed to parse config file: $config_file"
        return 1
    }
    if [[ -z "$parsed" ]]; then
        log_error "Config file parsed to empty output: $config_file"
        return 1
    fi
    eval "$parsed"

    # Apply environment variable overrides for backward compat
    _apply_env_overrides

    # Export all CFG_* variables
    _export_cfg_vars
}

# =============================================================================
# Environment variable overrides (legacy support)
# =============================================================================
# shellcheck disable=SC2034  # CFG_* variables are used via indirect expansion
_apply_env_overrides() {
    # AUTO_YES -> general.auto_yes
    if [[ -n "${AUTO_YES:-}" ]]; then
        CFG_GENERAL_AUTO_YES="$AUTO_YES"
    fi

    # SKIP_DOCKER -> docker.enabled (inverted)
    if [[ "${SKIP_DOCKER:-}" == "true" ]]; then
        CFG_DOCKER_ENABLED="false"
    fi

    # PYTHON_VERSION -> languages.python.version
    if [[ -n "${PYTHON_VERSION:-}" ]]; then
        CFG_LANGUAGES_PYTHON_VERSION="$PYTHON_VERSION"
    fi

    # NODE_VERSION -> languages.node.version
    if [[ -n "${NODE_VERSION:-}" ]]; then
        CFG_LANGUAGES_NODE_VERSION="$NODE_VERSION"
    fi

    # SKIP_CONDA -> languages.conda.enabled (inverted)
    if [[ "${SKIP_CONDA:-}" == "true" ]]; then
        CFG_LANGUAGES_CONDA_ENABLED="false"
    fi

    # SKIP_CLI_TOOLS -> cli_tools.enabled
    if [[ "${SKIP_CLI_TOOLS:-}" == "true" ]]; then
        CFG_CLI_TOOLS_ENABLED="false"
    fi

    # SKIP_SHELL_SETUP -> shell.enabled
    if [[ "${SKIP_SHELL_SETUP:-}" == "true" ]]; then
        CFG_SHELL_ENABLED="false"
    fi

    # SKIP_TMUX_CONFIG -> tmux.enabled
    if [[ "${SKIP_TMUX_CONFIG:-}" == "true" ]]; then
        CFG_TMUX_ENABLED="false"
    fi
}

# Export all CFG_* variables to the environment
_export_cfg_vars() {
    local var
    for var in "${!CFG_@}"; do
        export "${var?}"
    done
}
