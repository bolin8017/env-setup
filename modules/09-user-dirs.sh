#!/usr/bin/env bash
# 09-user-dirs.sh — Create personal user directories under $HOME
# Dependencies: lib/common.sh, lib/config.sh, lib/dryrun.sh

# =============================================================================
# _create_user_dir — Create one directory under $HOME (idempotent, best-effort)
# Rejects absolute paths, ~/ prefix, and '..' components per schema contract.
# Refuses to clobber an existing non-directory target.
# =============================================================================
_create_user_dir() {
    local rel_path="$1"

    if [[ "$rel_path" == /* ]]; then
        log_warn "Absolute paths not allowed in user_dirs.paths: $rel_path (skipped)"
        return 0
    fi

    # shellcheck disable=SC2088  # matching literal '~', not expanding it
    if [[ "$rel_path" == "~" ]] || [[ "$rel_path" == "~/"* ]]; then
        log_warn "Drop the leading '~/' — paths are already relative to \$HOME: $rel_path (skipped)"
        return 0
    fi

    if [[ "$rel_path" == *".."* ]]; then
        log_warn "Paths containing '..' not allowed: $rel_path (skipped)"
        return 0
    fi

    local target="$HOME/$rel_path"

    if [[ -e "$target" ]] && [[ ! -d "$target" ]]; then
        log_warn "Path exists but is not a directory: $target (skipped)"
        return 0
    fi

    if [[ -d "$target" ]]; then
        log_info "Already exists: $target"
        return 0
    fi

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

# =============================================================================
# uninstall_user_dirs — Reclaim only the EMPTY directories env-setup created.
# Non-empty directories (real user data) are always preserved. Uses rmdir, which
# physically cannot delete a non-empty directory. Skipped under --keep-tools.
# =============================================================================
uninstall_user_dirs() {
    print_header "Uninstall: User Directories"

    if [[ "${KEEP_TOOLS:-false}" == "true" ]]; then
        log_info "Skipping user-dir reclamation (--keep-tools)"
        return 0
    fi

    local -a paths=()
    local p
    while IFS= read -r p; do
        [[ -n "$p" ]] && paths+=("$p")
    done < <(cfg_list "user_dirs.paths")

    for p in "${paths[@]}"; do
        local target="${HOME}/${p}"
        if [[ ! -d "$target" ]]; then
            log_info "[SKIP] ${p} not present"
            continue
        fi
        if [[ -n "$(ls -A "$target" 2>/dev/null)" ]]; then
            log_info "${p} contains data — left intact"
            continue
        fi
        if [[ "${DRY_RUN:-false}" == "true" ]]; then
            echo "[DRY-RUN] Would rmdir empty: ${target}"
        elif rmdir "$target" 2>/dev/null; then
            log_success "Removed empty dir ${p}"
        else
            log_info "${p} not removable — left intact"
        fi
    done

    log_success "User directories uninstall complete"
}
