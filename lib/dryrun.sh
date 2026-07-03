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
# dry_run_rm — Remove a path recursively (or print what would be removed)
# =============================================================================
dry_run_rm() {
    if [[ "$DRY_RUN" == "true" ]]; then
        echo "[DRY-RUN] Would remove: $*"
        return 0
    fi
    rm -rf "$@"
}

# =============================================================================
# deploy_config — Copy a config file with overwrite protection.
# Modes (mainstream dpkg/chezmoi style):
#   KEEP_EXISTING=true → skip if dest exists
#   AUTO_YES=true      → overwrite without prompting
#   default            → show a one-line diff summary then ask y/N
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
        # A dry run must never block on a prompt: nothing will be mutated, so
        # just preview the decision that a real run would ask about.
        if [[ "${DRY_RUN:-false}" == "true" ]]; then
            if cmp -s "$src" "$dest" 2>/dev/null; then
                log_info "${label}: identical to repo version — skipping"
            else
                echo "[DRY-RUN] Would ask to overwrite ${dest} (differs from repo)"
            fi
            return 0
        fi
        if [[ "${KEEP_EXISTING:-false}" == "true" ]]; then
            log_info "[SKIP] Keeping existing ${label} (--keep-existing)"
            return 0
        fi

        if [[ "${AUTO_YES:-false}" == "true" ]]; then
            log_info "Overwriting ${label} (auto-yes)"
        else
            # Show one-line diff summary so the user can decide informed
            local src_lines dest_lines
            src_lines=$(wc -l < "$src" 2>/dev/null || echo "?")
            dest_lines=$(wc -l < "$dest" 2>/dev/null || echo "?")
            if cmp -s "$src" "$dest" 2>/dev/null; then
                log_info "${label}: identical to repo version — skipping"
                return 0
            fi
            log_info "${label}: existing ${dest_lines} lines → repo ${src_lines} lines"

            if ! ask_yes_no "Overwrite ${dest}?"; then
                log_info "[SKIP] Keeping existing ${label}"
                return 0
            fi
        fi
    fi

    dry_run_cp "$src" "$dest"
    log_success "Deployed ${label}"
}

# =============================================================================
# write_generated_fragment — Write a module-generated zsh fragment from stdin.
# Content-compared, not marker-guarded: an existing fragment with stale content
# is rewritten, so fragment fixes actually reach already-provisioned machines
# via self-update. Identical content is a silent no-op. Honours DRY_RUN.
# Usage: write_generated_fragment <name> << 'FRAGMENT' ... FRAGMENT
# =============================================================================
write_generated_fragment() {
    local name="$1"
    local dest_dir="$HOME/.config/zsh/fragments"
    local dest="$dest_dir/$name"
    local content
    content="$(cat)"

    if [[ -f "$dest" ]] && [[ "$(cat "$dest")" == "$content" ]]; then
        return 0
    fi

    if [[ "$DRY_RUN" == "true" ]]; then
        echo "[DRY-RUN] Would write fragment: $dest"
        return 0
    fi

    mkdir -p "$dest_dir"
    printf '%s\n' "$content" > "$dest"
    log_info "Wrote fragment: $dest"
}
