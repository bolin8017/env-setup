#!/usr/bin/env bash
# 09-user-dirs.sh — Create personal user directories under $HOME
# Dependencies: lib/common.sh, lib/config.sh, lib/dryrun.sh

# =============================================================================
# _create_user_dir — Create one directory under $HOME (idempotent, best-effort)
# Stub: validation logic is added in a follow-up commit.
# =============================================================================
_create_user_dir() {
    local rel_path="$1"
    local target="$HOME/$rel_path"

    if dry_run_mkdir "$target"; then
        log_success "Created: $target"
    else
        log_error "Failed to create: $target"
    fi
}

# =============================================================================
# install_user_dirs — Main entry point
# =============================================================================
install_user_dirs() {
    if ! cfg_enabled "user_dirs.enabled"; then
        log_info "Skipping user directories (disabled in config)"
        return 0
    fi

    print_header "User Directories"

    # Read paths into array first to avoid stdin conflicts in the loop.
    local -a paths=()
    local p
    while IFS= read -r p; do
        [[ -n "$p" ]] && paths+=("$p")
    done < <(cfg_list "user_dirs.paths")

    if [[ ${#paths[@]} -eq 0 ]]; then
        log_warn "user_dirs.paths is empty — nothing to create"
        return 0
    fi

    for p in "${paths[@]}"; do
        _create_user_dir "$p"
    done

    log_success "User directories ready"
}
