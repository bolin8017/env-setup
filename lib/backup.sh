#!/usr/bin/env bash
# backup.sh — Backup and restore shell/tool configuration files
# Stores timestamped snapshots under ~/.env-setup/backups/

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    set -euo pipefail
fi

[[ -n "${_ENV_SETUP_BACKUP_LOADED:-}" ]] && return 0
_ENV_SETUP_BACKUP_LOADED=1

_BACKUP_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${_BACKUP_LIB_DIR}/common.sh"
# shellcheck source=lib/dryrun.sh
source "${_BACKUP_LIB_DIR}/dryrun.sh"

BACKUP_DIR="${BACKUP_DIR:-$HOME/.env-setup/backups}"

# Files and directories to back up
BACKUP_TARGETS=(
    "$HOME/.zshrc"
    "$HOME/.p10k.zsh"
    "$HOME/.oh-my-zsh"
    "$HOME/.tmux.conf"
    "$HOME/.config/zsh"
)

# =============================================================================
# backup_configs — Create a timestamped backup of config files
# =============================================================================
backup_configs() {
    local timestamp
    timestamp="$(date +"%Y%m%d_%H%M%S")"
    local backup_path="${BACKUP_DIR}/backup_${timestamp}"

    dry_run_mkdir "$backup_path"
    log_info "Creating backup at: $backup_path"

    local backed_up=false
    local target
    for target in "${BACKUP_TARGETS[@]}"; do
        [[ -e "$target" ]] || continue

        local name
        name="$(basename "$target")"
        log_info "  Backing up: $target"

        dry_run_cp "$target" "$backup_path/$name"
        backed_up=true
    done

    if [[ "$backed_up" == true ]]; then
        if [[ "${DRY_RUN:-false}" != "true" ]]; then
            echo "$backup_path" > "${BACKUP_DIR}/.latest"
            _prune_old_backups
        fi
        log_success "Backup created: $backup_path"
    else
        log_warn "No configuration files found to back up"
        if [[ "${DRY_RUN:-false}" != "true" ]]; then
            rm -rf "$backup_path"
        fi
    fi
}

# =============================================================================
# _prune_old_backups — Keep only the newest BACKUP_KEEP snapshots.
# Every setup run snapshots (including the full ~/.oh-my-zsh tree), and
# nothing ever pruned - tens of MB per run, forever. Timestamped names sort
# lexically, so "newest" is just the sorted tail.
# =============================================================================
BACKUP_KEEP="${BACKUP_KEEP:-5}"

_prune_old_backups() {
    local dirs=() d
    for d in "$BACKUP_DIR"/backup_*; do
        [[ -d "$d" ]] && dirs+=("$d")
    done
    local excess=$(( ${#dirs[@]} - BACKUP_KEEP ))
    (( excess <= 0 )) && return 0

    # Never prune the snapshot .latest points at (restore_configs needs it).
    local latest=""
    [[ -f "${BACKUP_DIR}/.latest" ]] && latest="$(cat "${BACKUP_DIR}/.latest")"

    local i=0
    for d in "${dirs[@]}"; do
        (( i >= excess )) && break
        if [[ "$d" == "$latest" ]]; then continue; fi
        rm -rf "$d"
        log_info "  Pruned old backup: $(basename "$d")"
        i=$((i + 1))
    done
}

# =============================================================================
# restore_configs — Restore from latest or specified backup
# Usage: restore_configs [backup_name]
# =============================================================================
restore_configs() {
    local backup_path="${1:-}"

    if [[ -z "$backup_path" ]]; then
        # Use latest backup
        if [[ -f "${BACKUP_DIR}/.latest" ]]; then
            backup_path="$(cat "${BACKUP_DIR}/.latest")"
        else
            log_error "No backup specified and no latest backup found"
            return 1
        fi
    else
        # Allow passing just the directory name
        if [[ ! -d "$backup_path" ]] && [[ -d "${BACKUP_DIR}/${backup_path}" ]]; then
            backup_path="${BACKUP_DIR}/${backup_path}"
        fi
    fi

    if [[ ! -d "$backup_path" ]]; then
        log_error "Backup not found: $backup_path"
        return 1
    fi

    log_info "Restoring from: $backup_path"

    local file
    for file in "$backup_path"/*; do
        [[ -e "$file" ]] || continue

        local name
        name="$(basename "$file")"
        local target="$HOME/$name"

        # Handle .config/* targets
        local original_target=""
        for t in "${BACKUP_TARGETS[@]}"; do
            if [[ "$(basename "$t")" == "$name" ]]; then
                original_target="$t"
                break
            fi
        done
        target="${original_target:-$HOME/$name}"

        log_info "  Restoring: $name -> $target"

        [[ -e "$target" ]] && dry_run_cmd rm -rf "$target"

        dry_run_mkdir "$(dirname "$target")"
        dry_run_cp "$file" "$target"
    done

    log_success "Restore complete"
}

# =============================================================================
# list_backups — Show all available backups
# =============================================================================
list_backups() {
    if [[ ! -d "$BACKUP_DIR" ]]; then
        log_warn "No backups found"
        return 0
    fi

    local count=0
    local latest=""
    [[ -f "${BACKUP_DIR}/.latest" ]] && latest="$(cat "${BACKUP_DIR}/.latest")"

    local entry
    for entry in "$BACKUP_DIR"/backup_*; do
        [[ -d "$entry" ]] || continue
        local label=""
        [[ "$entry" == "$latest" ]] && label=" ${GREEN}(latest)${NC}"
        echo -e "  $(basename "$entry")${label}"
        # count+1, not ((count++)): post-increment from 0 evaluates to 0,
        # which is exit status 1 - fatal under the standalone errexit.
        count=$((count + 1))
    done

    if [[ $count -eq 0 ]]; then
        log_warn "No backups found"
    else
        log_info "Total: $count backup(s)"
    fi
}

# Standalone execution support
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    case "${1:-backup}" in
        backup)  backup_configs ;;
        restore) restore_configs "${2:-}" ;;
        list)    list_backups ;;
        *)       echo "Usage: $0 {backup|list|restore [backup_name]}"; exit 1 ;;
    esac
fi
