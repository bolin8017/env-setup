#!/usr/bin/env bash
# uninstall.sh — Shared safety primitives for the teardown engine.
# Protected-path guard + managed-file/dir removal helpers. Mirrors the safety
# model in docs/superpowers/specs/2026-06-02-uninstall-scripts-design.md.

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    set -euo pipefail
fi

[[ -n "${_ENV_SETUP_UNINSTALL_LOADED:-}" ]] && return 0
_ENV_SETUP_UNINSTALL_LOADED=1

_UNINSTALL_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${_UNINSTALL_LIB_DIR}/common.sh"
# shellcheck source=lib/dryrun.sh
source "${_UNINSTALL_LIB_DIR}/dryrun.sh"

# Layer flags — default false so the lib is safe to source in tests / standalone.
KEEP_TOOLS="${KEEP_TOOLS:-false}"
PURGE="${PURGE:-false}"
NO_RESTORE="${NO_RESTORE:-false}"

# Newline-separated absolute paths the caller marks as protected (e.g. the
# configured user_dirs.paths). Set by uninstall.sh before running modules.
PROTECTED_EXTRA="${PROTECTED_EXTRA:-}"

# Backups root (kept in sync with lib/backup.sh's default).
BACKUP_DIR="${BACKUP_DIR:-$HOME/.env-setup/backups}"

# _abs <path> — best-effort absolutise + ~ expansion (no realpath dependency).
_abs() {
    local p="$1"
    # shellcheck disable=SC2088  # matching a literal leading '~', not expanding it
    [[ "$p" == "~" ]] && p="$HOME"
    # shellcheck disable=SC2088  # matching a literal '~/' prefix, not expanding it
    [[ "$p" == "~/"* ]] && p="$HOME/${p#\~/}"
    [[ "$p" != /* ]] && p="$PWD/$p"
    echo "${p%/}"
}

# =============================================================================
# is_protected_path <path> — return 0 if the path must never be removed.
# Protects: $HOME itself; the backups tree; Claude credentials/history/projects;
# and any caller-supplied PROTECTED_EXTRA path (and everything under it).
# =============================================================================
is_protected_path() {
    local abs
    abs="$(_abs "$1")"

    [[ "$abs" == "$HOME" ]] && return 0

    local backups="${BACKUP_DIR%/}"
    [[ "$abs" == "$backups" || "$abs" == "$backups/"* ]] && return 0

    local claude="$HOME/.claude" p
    for p in .credentials.json projects todos shell-snapshots statsig; do
        [[ "$abs" == "$claude/$p" || "$abs" == "$claude/$p/"* ]] && return 0
    done
    # history files (history.jsonl, history/, …)
    [[ "$abs" == "$claude/history"* ]] && return 0

    if [[ -n "$PROTECTED_EXTRA" ]]; then
        local extra
        while IFS= read -r extra; do
            [[ -z "$extra" ]] && continue
            extra="${extra%/}"
            [[ "$abs" == "$extra" || "$abs" == "$extra/"* ]] && return 0
        done <<< "$PROTECTED_EXTRA"
    fi

    return 1
}

# =============================================================================
# remove_managed_file <dest> <repo_src> [<label>]
# Removes dest only when it is byte-identical to the repo source (i.e. env-setup
# deployed it and the user never edited it). A modified file is preserved and
# reported — never deleted. Protected paths are refused.
# =============================================================================
remove_managed_file() {
    local dest="$1" repo_src="$2"
    local label="${3:-$(basename "$dest")}"

    if [[ ! -e "$dest" ]]; then
        log_info "[SKIP] ${label} not present"
        return 0
    fi
    if is_protected_path "$dest"; then
        log_warn "Refusing to remove protected path: ${dest}"
        return 0
    fi
    if [[ -z "$repo_src" || ! -f "$repo_src" ]]; then
        log_warn "${label}: cannot verify (no repo source) — preserved"
        return 0
    fi
    if ! cmp -s "$repo_src" "$dest" 2>/dev/null; then
        log_warn "${label} modified locally — preserved (remove manually if desired)"
        return 0
    fi
    dry_run_rm "$dest"
    log_success "Removed ${label}"
}
