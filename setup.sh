#!/usr/bin/env bash
# setup.sh — Main entry point for env-setup
# Usage: ./setup.sh [--dry-run] [--auto-yes] [--config <path>] [--verify] [--modules <list>] [--help]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export ENV_SETUP_DIR="$SCRIPT_DIR"

# =============================================================================
# Parse CLI arguments (before sourcing libs so flags are available immediately)
# =============================================================================
CLI_DRY_RUN=""
CLI_AUTO_YES=""
CLI_CONFIG=""
CLI_VERIFY_ONLY=""
CLI_MODULES=""

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --dry-run)
                CLI_DRY_RUN="true"
                shift
                ;;
            --auto-yes|-y)
                CLI_AUTO_YES="true"
                shift
                ;;
            --config)
                if [[ -z "${2:-}" ]]; then
                    echo "Error: --config requires a file path" >&2
                    exit 1
                fi
                CLI_CONFIG="$2"
                shift 2
                ;;
            --verify)
                CLI_VERIFY_ONLY="true"
                shift
                ;;
            --modules)
                if [[ -z "${2:-}" ]]; then
                    echo "Error: --modules requires a comma-separated list" >&2
                    exit 1
                fi
                CLI_MODULES="$2"
                shift 2
                ;;
            --help|-h)
                show_usage
                exit 0
                ;;
            *)
                echo "Unknown option: $1" >&2
                show_usage
                exit 1
                ;;
        esac
    done
}

show_usage() {
    cat << 'EOF'
Usage: ./setup.sh [OPTIONS]

Options:
  --dry-run              Print what would be done without making changes
  --auto-yes, -y         Skip all interactive prompts (assume yes)
  --config <path>        Use a custom config.yaml file
  --verify               Run verification only (no installation)
  --modules <list>       Comma-separated list of modules to run
                         e.g. --modules 01-core,06-shell
  --help, -h             Show this help message

Examples:
  ./setup.sh                          # Full installation (uses config.yaml)
  ./setup.sh --dry-run                # Preview without changes
  ./setup.sh --auto-yes               # Non-interactive installation
  ./setup.sh --modules 01-core,06-shell  # Install only specific modules
  ./setup.sh --verify                 # Check what is already installed

Configuration:
  Copy config.yaml.example to config.yaml and edit to customise.
  CLI flags override config.yaml values.
EOF
}

# Parse arguments before anything else (--help must work without libs)
parse_args "$@"

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

# =============================================================================
# Ensure log directory exists before any logging happens (load_config logs)
# =============================================================================
setup_logging

# =============================================================================
# Load configuration
# =============================================================================
load_config "${CLI_CONFIG:-${SCRIPT_DIR}/config.yaml}"

# Apply config.yaml dry_run setting, then let CLI flags override
[[ "${CFG_GENERAL_DRY_RUN:-}" == "true" ]] && DRY_RUN="true"
[[ "${CLI_DRY_RUN:-}" == "true" ]] && DRY_RUN="true"
AUTO_YES="${CFG_GENERAL_AUTO_YES:-${AUTO_YES:-false}}"
[[ "${CLI_AUTO_YES:-}" == "true" ]] && AUTO_YES="true"

# =============================================================================
# Verify-only mode
# =============================================================================
if [[ "${CLI_VERIFY_ONLY:-}" == "true" ]]; then
    exec bash "${SCRIPT_DIR}/scripts/verify.sh"
fi

# =============================================================================
# Welcome banner
# =============================================================================
show_welcome() {
    local os arch shell dry_status
    os="$(detect_os)"
    arch="$(detect_arch)"
    shell="$(detect_shell)"
    dry_status="off"
    [[ "${DRY_RUN:-false}" == "true" ]] && dry_status="${YELLOW}ON${NC}"

    echo ""
    echo -e "${BLUE}╔═══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║${NC}                                                           ${BLUE}║${NC}"
    echo -e "${BLUE}║${NC}  ${BOLD}env-setup${NC}  — Development Environment Installer          ${BLUE}║${NC}"
    echo -e "${BLUE}║${NC}                                                           ${BLUE}║${NC}"
    echo -e "${BLUE}╚═══════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "  ${CYAN}OS:${NC}       ${os}"
    echo -e "  ${CYAN}Arch:${NC}     ${arch}"
    echo -e "  ${CYAN}Shell:${NC}    ${shell}"
    echo -e "  ${CYAN}Dry-run:${NC}  ${dry_status}"
    echo ""
}

show_welcome

# =============================================================================
# Module runner
# =============================================================================

# Track results for summary
declare -a MODULES_INSTALLED=()
declare -a MODULES_SKIPPED=()
declare -a MODULES_FAILED=()

# Check whether a module should run based on --modules filter
_module_in_filter() {
    local module_name="$1"

    # No filter means run everything
    [[ -z "${CLI_MODULES:-}" ]] && return 0

    local IFS=','
    local entry
    for entry in $CLI_MODULES; do
        # Match on full name or numeric prefix
        if [[ "$entry" == "$module_name" ]] || [[ "$module_name" == "${entry}-"* ]]; then
            return 0
        fi
    done
    return 1
}

# run_module <module-name> <install-function>
# Sources modules/<module-name>.sh, then calls <install-function>.
# Errors are caught and logged; execution continues with the next module.
run_module() {
    local module_name="$1"
    local install_fn="$2"
    local module_file="${SCRIPT_DIR}/modules/${module_name}.sh"

    # Check --modules filter
    if ! _module_in_filter "$module_name"; then
        MODULES_SKIPPED+=("$module_name (filtered)")
        return 0
    fi

    # Check if the module file exists
    if [[ ! -f "$module_file" ]]; then
        log_warn "Module file not found: ${module_file} — skipping"
        MODULES_SKIPPED+=("$module_name (missing)")
        return 0
    fi

    print_header "$module_name"

    # Source the module
    # shellcheck source=/dev/null
    source "$module_file"

    # Verify the function exists
    if ! declare -f "$install_fn" &>/dev/null; then
        log_error "Function $install_fn not found in $module_file"
        MODULES_FAILED+=("$module_name")
        return 0
    fi

    # Run the function, catch errors
    if "$install_fn"; then
        MODULES_INSTALLED+=("$module_name")
    else
        log_error "Module $module_name failed"
        MODULES_FAILED+=("$module_name")
    fi
}

# =============================================================================
# Verification
# =============================================================================
run_verification() {
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_info "Skipping verification in dry-run mode"
        return 0
    fi

    if [[ -x "${SCRIPT_DIR}/scripts/verify.sh" ]]; then
        print_header "Verification"
        bash "${SCRIPT_DIR}/scripts/verify.sh" || true
    fi
}

# =============================================================================
# Summary
# =============================================================================
show_summary() {
    echo ""
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BOLD}${BLUE}  Installation Summary${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""

    if [[ ${#MODULES_INSTALLED[@]} -gt 0 ]]; then
        echo -e "  ${GREEN}Installed:${NC}"
        for m in "${MODULES_INSTALLED[@]}"; do
            echo -e "    ${GREEN}[OK]${NC}   $m"
        done
    fi

    if [[ ${#MODULES_SKIPPED[@]} -gt 0 ]]; then
        echo -e "  ${YELLOW}Skipped:${NC}"
        for m in "${MODULES_SKIPPED[@]}"; do
            echo -e "    ${YELLOW}[SKIP]${NC} $m"
        done
    fi

    if [[ ${#MODULES_FAILED[@]} -gt 0 ]]; then
        echo -e "  ${RED}Failed:${NC}"
        for m in "${MODULES_FAILED[@]}"; do
            echo -e "    ${RED}[FAIL]${NC} $m"
        done
    fi

    echo ""
    echo -e "  ${CYAN}Total:${NC} ${#MODULES_INSTALLED[@]} installed, ${#MODULES_SKIPPED[@]} skipped, ${#MODULES_FAILED[@]} failed"
    echo ""

    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        echo -e "  ${YELLOW}This was a dry run — no changes were made.${NC}"
        echo ""
    fi

    echo -e "  ${CYAN}Logs:${NC}     ${INSTALL_LOG}"
    echo -e "  ${CYAN}Verify:${NC}   ./scripts/verify.sh"
    echo ""
    echo -e "  ${CYAN}Next steps:${NC}"
    echo "    1. Restart your terminal or run: source $(shell_rc_file)"
    echo "    2. Authenticate GitHub CLI:  gh auth login"
    echo ""
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
}

# =============================================================================
# Main execution
# =============================================================================

# Backup existing configs
if cfg_enabled "general.backup"; then
    print_header "Backup"
    backup_configs
fi

# Run modules in dependency order
run_module "01-core"         "install_core"
run_module "02-languages"    "install_languages"
run_module "03-python-tools" "install_python_tools"
run_module "04-docker"       "install_docker"
run_module "05-cli-tools"    "install_cli_tools"
run_module "06-shell"        "install_shell"
run_module "07-tmux"         "install_tmux"

# Claude Code (standalone — no Node.js dependency)
run_module "08-claude-code" "install_claude_code"

# Verification
run_verification

# Summary
show_summary
