#!/usr/bin/env bash
# uninstall.sh — Teardown entry point for env-setup (macOS/Linux/WSL).
# Sibling of setup.sh. Runs each module's uninstall_<module> in reverse order.
# Usage: ./uninstall.sh [--dry-run] [--auto-yes] [--keep-tools] [--purge]
#                       [--no-restore] [--config <path>] [--modules <list>] [--help]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export ENV_SETUP_DIR="$SCRIPT_DIR"

CLI_DRY_RUN=""
CLI_AUTO_YES=""
CLI_KEEP_TOOLS=""
CLI_PURGE=""
CLI_NO_RESTORE=""
CLI_CONFIG=""
CLI_MODULES=""

show_usage() {
    cat << 'EOF'
Usage: ./uninstall.sh [OPTIONS]

Removes what env-setup installed. Conservative by default.

Options:
  --dry-run           Print what would be removed without making changes
  --auto-yes, -y      Remove without prompting (protected paths still blocked)
  --keep-tools        Remove only the config/dotfile layer; keep user-space
                      tools (nvm, pyenv, oh-my-zsh, plugins, CLI binaries)
  --purge             Also remove system packages (apt/brew), revert the default
                      shell, and clean apt sources / keyrings / docker group
  --no-restore        Skip restoring pre-install dotfiles from backup
  --config <path>     Use a custom config.yaml (read only for protected paths)
  --modules <list>    Comma-separated modules to uninstall, e.g. 01-core,06-shell
  --help, -h          Show this help message

Layers:
  default             config/dotfile layer + user-space tool layer
  --keep-tools        config/dotfile layer only
  --purge             config + tools + system packages + system state

Never removed: personal data directories, Claude credentials/history, and the
~/.env-setup/backups tree.
EOF
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --dry-run)     CLI_DRY_RUN="true"; shift ;;
            --auto-yes|-y) CLI_AUTO_YES="true"; shift ;;
            --keep-tools)  CLI_KEEP_TOOLS="true"; shift ;;
            --purge)       CLI_PURGE="true"; shift ;;
            --no-restore)  CLI_NO_RESTORE="true"; shift ;;
            --config)
                if [[ -z "${2:-}" ]]; then echo "Error: --config requires a path" >&2; exit 1; fi
                CLI_CONFIG="$2"; shift 2 ;;
            --modules)
                if [[ -z "${2:-}" ]]; then echo "Error: --modules requires a list" >&2; exit 1; fi
                CLI_MODULES="$2"; shift 2 ;;
            --help|-h)     show_usage; exit 0 ;;
            *)             echo "Unknown option: $1" >&2; show_usage; exit 1 ;;
        esac
    done
}

parse_args "$@"

# =============================================================================
# Logging — separate uninstall log (set before sourcing common.sh)
# =============================================================================
export INSTALL_LOG="${HOME}/.env-setup/uninstall.log"

# =============================================================================
# Source libraries
# =============================================================================
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"
# shellcheck source=lib/yaml.sh
source "${SCRIPT_DIR}/lib/yaml.sh"
# shellcheck source=lib/config.sh
source "${SCRIPT_DIR}/lib/config.sh"
# shellcheck source=lib/package.sh
source "${SCRIPT_DIR}/lib/package.sh"
# shellcheck source=lib/dryrun.sh
source "${SCRIPT_DIR}/lib/dryrun.sh"
# shellcheck source=lib/backup.sh
source "${SCRIPT_DIR}/lib/backup.sh"
# shellcheck source=lib/uninstall.sh
source "${SCRIPT_DIR}/lib/uninstall.sh"

setup_logging
load_config "${CLI_CONFIG:-${SCRIPT_DIR}/config.yaml}"

# =============================================================================
# Resolve flags
# =============================================================================
DRY_RUN="${DRY_RUN:-false}"
[[ "${CLI_DRY_RUN:-}" == "true" ]] && DRY_RUN="true"
AUTO_YES="false"
[[ "${CLI_AUTO_YES:-}" == "true" ]] && AUTO_YES="true"
KEEP_TOOLS="false"
[[ "${CLI_KEEP_TOOLS:-}" == "true" ]] && KEEP_TOOLS="true"
PURGE="false"
[[ "${CLI_PURGE:-}" == "true" ]] && PURGE="true"
NO_RESTORE="false"
[[ "${CLI_NO_RESTORE:-}" == "true" ]] && NO_RESTORE="true"
export DRY_RUN AUTO_YES KEEP_TOOLS PURGE NO_RESTORE

# Mark configured user_dirs.paths as protected (absolute, newline-separated).
PROTECTED_EXTRA="$(while IFS= read -r p; do [[ -n "$p" ]] && echo "${HOME}/${p}"; done < <(cfg_list "user_dirs.paths"))"
export PROTECTED_EXTRA

# =============================================================================
# Banner
# =============================================================================
show_welcome() {
    local dry_status="off"
    [[ "${DRY_RUN}" == "true" ]] && dry_status="${YELLOW}ON${NC}"
    echo ""
    echo -e "${RED}╔═══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${RED}║${NC}  ${BOLD}env-setup${NC}  — Uninstaller                              ${RED}║${NC}"
    echo -e "${RED}╚═══════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "  ${CYAN}OS:${NC}          $(detect_os)"
    echo -e "  ${CYAN}Dry-run:${NC}     ${dry_status}"
    echo -e "  ${CYAN}Keep tools:${NC}  ${KEEP_TOOLS}"
    echo -e "  ${CYAN}Purge pkgs:${NC}  ${PURGE}"
    echo ""
}
show_welcome

# =============================================================================
# Global confirmation
# =============================================================================
if [[ "${DRY_RUN}" != "true" && "${AUTO_YES}" != "true" ]]; then
    echo -e "  This removes env-setup-managed files"
    [[ "${KEEP_TOOLS}" != "true" ]] && echo "  and user-space tools (nvm, pyenv, oh-my-zsh, …)"
    [[ "${PURGE}" == "true" ]] && echo -e "  ${RED}and system packages (git, docker, …) via --purge${NC}"
    echo ""
    if ! ask_yes_no "Continue?"; then
        log_info "Aborted by user"
        exit 0
    fi
fi

# =============================================================================
# Module runner (reverse order)
# =============================================================================
declare -a REMOVED=() FAILED=() SKIPPED=()

_module_in_filter() {
    local module_name="$1"
    [[ -z "${CLI_MODULES:-}" ]] && return 0
    local IFS=','
    local entry
    for entry in $CLI_MODULES; do
        if [[ "$entry" == "$module_name" ]] || [[ "$module_name" == "${entry}-"* ]]; then
            return 0
        fi
    done
    return 1
}

run_uninstall_module() {
    local module_name="$1" fn="$2"
    local module_file="${SCRIPT_DIR}/modules/${module_name}.sh"

    if ! _module_in_filter "$module_name"; then
        SKIPPED+=("$module_name (filtered)"); return 0
    fi
    if [[ ! -f "$module_file" ]]; then
        log_warn "Module not found: ${module_file}"; SKIPPED+=("$module_name (missing)"); return 0
    fi
    # shellcheck source=/dev/null
    source "$module_file"
    if ! declare -f "$fn" >/dev/null; then
        log_error "Function $fn not found in $module_file"; FAILED+=("$module_name"); return 0
    fi
    if "$fn"; then REMOVED+=("$module_name"); else log_error "Module $module_name failed"; FAILED+=("$module_name"); fi
}

# Reverse dependency order (09 → 01)
run_uninstall_module "09-user-dirs"    "uninstall_user_dirs"
run_uninstall_module "08-claude-code"  "uninstall_claude_code"
run_uninstall_module "07-tmux"         "uninstall_tmux"
run_uninstall_module "06-shell"        "uninstall_shell"
run_uninstall_module "05-cli-tools"    "uninstall_cli_tools"
run_uninstall_module "04-docker"       "uninstall_docker"
run_uninstall_module "03-python-tools" "uninstall_python_tools"
run_uninstall_module "02-languages"    "uninstall_languages"
run_uninstall_module "01-core"         "uninstall_core"

# =============================================================================
# Restore pre-install dotfiles (last)
# =============================================================================
if [[ "${NO_RESTORE}" != "true" ]] && [[ -f "${BACKUP_DIR}/.latest" ]]; then
    print_header "Restore original configs"
    restore_configs || log_warn "Restore reported a problem (continuing)"
fi

# =============================================================================
# Summary
# =============================================================================
echo ""
echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BOLD}${RED}  Uninstall Summary${NC}"
echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
[[ ${#REMOVED[@]} -gt 0 ]] && { echo -e "  ${GREEN}Processed:${NC}"; for m in "${REMOVED[@]}"; do echo "    [OK]   $m"; done; }
[[ ${#SKIPPED[@]} -gt 0 ]] && { echo -e "  ${YELLOW}Skipped:${NC}"; for m in "${SKIPPED[@]}"; do echo "    [SKIP] $m"; done; }
[[ ${#FAILED[@]}  -gt 0 ]] && { echo -e "  ${RED}Failed:${NC}"; for m in "${FAILED[@]}"; do echo "    [FAIL] $m"; done; }
echo ""
[[ "${DRY_RUN}" == "true" ]] && echo -e "  ${YELLOW}This was a dry run — no changes were made.${NC}"
echo -e "  ${CYAN}Log:${NC} ${INSTALL_LOG}"
echo -e "  ${CYAN}Note:${NC} ~/.env-setup (logs + backups) was kept; delete it manually when ready."
echo ""

show_missing_apt_summary
