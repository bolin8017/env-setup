#!/usr/bin/env bash
# dryrun.sh — Dry-run wrappers for commands, file copies, and directory creation
# When DRY_RUN=true, actions are printed instead of executed.

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    set -euo pipefail
fi

[[ -n "${_ENV_SETUP_DRYRUN_LOADED:-}" ]] && return 0
_ENV_SETUP_DRYRUN_LOADED=1

# DRY_RUN can be set via CFG_GENERAL_DRY_RUN, CLI flag, or directly
DRY_RUN="${DRY_RUN:-${CFG_GENERAL_DRY_RUN:-false}}"

# =============================================================================
# dry_run_cmd — Execute or print a command
# =============================================================================
dry_run_cmd() {
    if [[ "$DRY_RUN" == "true" ]]; then
        echo "[DRY-RUN] Would run: $*"
        return 0
    fi
    "$@"
}

# =============================================================================
# dry_run_cp — Copy files (or print what would be copied)
# =============================================================================
dry_run_cp() {
    if [[ "$DRY_RUN" == "true" ]]; then
        echo "[DRY-RUN] Would copy: $1 -> $2"
        return 0
    fi
    cp -a "$1" "$2"
}

# =============================================================================
# dry_run_mkdir — Create directory (or print what would be created)
# =============================================================================
dry_run_mkdir() {
    if [[ "$DRY_RUN" == "true" ]]; then
        echo "[DRY-RUN] Would mkdir: $1"
        return 0
    fi
    mkdir -p "$1"
}

# =============================================================================
# deploy_config — Copy a config file with overwrite protection.
# If the destination exists and AUTO_YES is not true, ask user before overwriting.
# Fragments (managed files) should use dry_run_cp directly instead.
# Usage: deploy_config <src> <dest> [<label>]
# =============================================================================
deploy_config() {
    local src="$1"
    local dest="$2"
    local label="${3:-$(basename "$dest")}"

    if [[ ! -f "$src" ]]; then
        log_warn "${label} source not found: ${src}"
        return 0
    fi

    if [[ -f "$dest" ]]; then
        if [[ "${AUTO_YES:-false}" == "true" ]]; then
            log_info "Overwriting ${label} (auto-yes)"
        elif ! ask_yes_no "Overwrite ${dest}?"; then
            log_info "[SKIP] Keeping existing ${label}"
            return 0
        fi
    fi

    dry_run_cp "$src" "$dest"
    log_success "Deployed ${label}"
}
