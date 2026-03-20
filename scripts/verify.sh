#!/usr/bin/env bash
# verify.sh — Post-install verification for env-setup
# Checks every tool and config that setup.sh installs.
# Can be run standalone or called by setup.sh --verify.
set -o pipefail

# =============================================================================
# Colors
# =============================================================================
RED=$'\033[0;31m'
GREEN=$'\033[0;32m'
YELLOW=$'\033[1;33m'
CYAN=$'\033[0;36m'
BOLD=$'\033[1m'
NC=$'\033[0m'

# =============================================================================
# Setup tool paths so verify can find recently installed tools
# =============================================================================

# Homebrew (macOS Apple Silicon)
[[ -f "/opt/homebrew/bin/brew" ]] && eval "$(/opt/homebrew/bin/brew shellenv)" 2>/dev/null
# Homebrew (macOS Intel)
[[ -f "/usr/local/bin/brew" ]] && eval "$(/usr/local/bin/brew shellenv)" 2>/dev/null

# nvm
export NVM_DIR="${NVM_DIR:-$HOME/.nvm}"
# shellcheck source=/dev/null
[[ -s "$NVM_DIR/nvm.sh" ]] && source "$NVM_DIR/nvm.sh" 2>/dev/null

# fnm
command -v fnm &>/dev/null && eval "$(fnm env)" 2>/dev/null

# pyenv
export PYENV_ROOT="${PYENV_ROOT:-$HOME/.pyenv}"
export PATH="$PYENV_ROOT/bin:$PYENV_ROOT/shims:$PATH"
command -v pyenv &>/dev/null && eval "$(pyenv init --path)" 2>/dev/null

# Poetry / pipx / local bin
export PATH="$HOME/.local/bin:$PATH"

# Conda
# shellcheck source=/dev/null
[[ -f "$HOME/miniconda3/etc/profile.d/conda.sh" ]] && source "$HOME/miniconda3/etc/profile.d/conda.sh" 2>/dev/null

# =============================================================================
# Counters
# =============================================================================
PASS=0
FAIL=0
SKIP=0

# =============================================================================
# Check helpers
# =============================================================================

# check_cmd <command> [display-name]
# Checks whether a command is available in PATH.
check_cmd() {
    local cmd="$1"
    local name="${2:-$1}"

    printf "  %-30s " "$name"
    if command -v "$cmd" &>/dev/null; then
        echo -e "${GREEN}[PASS]${NC}"
        ((PASS++))
    else
        echo -e "${RED}[FAIL]${NC}"
        ((FAIL++))
    fi
}

# check_cmd_any <display-name> <cmd1> [cmd2 ...]
# Passes if ANY of the listed commands exist.
check_cmd_any() {
    local name="$1"
    shift

    printf "  %-30s " "$name"
    for cmd in "$@"; do
        if command -v "$cmd" &>/dev/null; then
            echo -e "${GREEN}[PASS]${NC}"
            ((PASS++))
            return 0
        fi
    done
    echo -e "${RED}[FAIL]${NC}"
    ((FAIL++))
}

# check_dir <path> [display-name]
# Checks whether a directory exists.
check_dir() {
    local dir="$1"
    local name="${2:-$1}"

    printf "  %-30s " "$name"
    if [[ -d "$dir" ]]; then
        echo -e "${GREEN}[PASS]${NC}"
        ((PASS++))
    else
        echo -e "${RED}[FAIL]${NC}"
        ((FAIL++))
    fi
}

# check_file <path> [display-name]
# Checks whether a file exists.
check_file() {
    local file="$1"
    local name="${2:-$1}"

    printf "  %-30s " "$name"
    if [[ -f "$file" ]]; then
        echo -e "${GREEN}[PASS]${NC}"
        ((PASS++))
    else
        echo -e "${RED}[FAIL]${NC}"
        ((FAIL++))
    fi
}

# check_skip <display-name> <reason>
# Mark a check as intentionally skipped.
check_skip() {
    local name="$1"
    local reason="$2"

    printf "  %-30s " "$name"
    echo -e "${YELLOW}[SKIP]${NC} $reason"
    ((SKIP++))
}

# =============================================================================
# Banner
# =============================================================================
echo ""
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BOLD}${CYAN}  env-setup — Verification Report${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

# =============================================================================
# Core
# =============================================================================
echo -e "${BOLD}Core${NC}"
if [[ "$(uname -s)" == "Darwin" ]]; then
    check_cmd brew "Homebrew"
else
    check_skip "Homebrew" "macOS only"
fi
check_cmd git       "git"
check_cmd gh        "GitHub CLI (gh)"
check_cmd gcc       "gcc"
check_cmd make      "make"
check_cmd cmake     "cmake"
echo ""

# =============================================================================
# Languages
# =============================================================================
echo -e "${BOLD}Languages${NC}"
check_cmd node      "Node.js"
check_cmd npm       "npm"
check_cmd_any       "nvm / fnm" nvm fnm
check_cmd python3   "Python 3"
check_cmd pyenv     "pyenv"
if command -v conda &>/dev/null; then
    check_cmd conda "Conda"
else
    check_skip "Conda" "disabled by default"
fi
echo ""

# =============================================================================
# Python Tools
# =============================================================================
echo -e "${BOLD}Python Tools${NC}"
check_cmd jupyter   "Jupyter"
check_cmd poetry    "Poetry"
check_cmd uv        "uv"
echo ""

# =============================================================================
# Docker
# =============================================================================
echo -e "${BOLD}Docker${NC}"
check_cmd docker    "docker"
echo ""

# =============================================================================
# CLI Tools
# =============================================================================
echo -e "${BOLD}CLI Tools${NC}"
check_cmd fzf       "fzf"
check_cmd rg        "ripgrep (rg)"
check_cmd_any       "bat" bat batcat
check_cmd jq        "jq"
check_cmd_any       "fd" fd fdfind
check_cmd eza       "eza"
check_cmd btop      "btop"
check_cmd tldr      "tldr"
check_cmd tree      "tree"
check_cmd_any       "httpie" http https
check_cmd zoxide    "zoxide"
echo ""

# =============================================================================
# Shell
# =============================================================================
echo -e "${BOLD}Shell${NC}"
check_cmd zsh                                           "zsh"
check_dir "$HOME/.oh-my-zsh"                            "Oh My Zsh"
check_dir "${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/themes/powerlevel10k"  "Powerlevel10k"
check_dir "${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins/zsh-autosuggestions"    "zsh-autosuggestions"
check_dir "${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins/zsh-syntax-highlighting" "zsh-syntax-highlighting"
check_dir "${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins/zsh-completions"        "zsh-completions"
echo ""

# =============================================================================
# Shell Config Files
# =============================================================================
echo -e "${BOLD}Shell Config${NC}"
# shellcheck disable=SC2088  # tilde is intentional display label
check_file "$HOME/.zshrc"                               "~/.zshrc"
# shellcheck disable=SC2088
check_dir  "$HOME/.config/zsh/fragments"                 "~/.config/zsh/fragments/"
# shellcheck disable=SC2088
check_file "$HOME/.config/zsh/aliases.zsh"               "~/.config/zsh/aliases.zsh"
# shellcheck disable=SC2088
check_file "$HOME/.p10k.zsh"                             "~/.p10k.zsh"
echo ""

# =============================================================================
# Tmux
# =============================================================================
echo -e "${BOLD}Tmux${NC}"
check_cmd  tmux                                          "tmux"
# shellcheck disable=SC2088
check_file "$HOME/.tmux.conf"                            "~/.tmux.conf"
# shellcheck disable=SC2088
check_dir  "$HOME/.tmux/plugins/tpm"                     "TPM (~/.tmux/plugins/tpm)"
echo ""

# =============================================================================
# Summary
# =============================================================================
TOTAL=$((PASS + FAIL))

echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "  ${GREEN}Passed:${NC}  $PASS"
echo -e "  ${RED}Failed:${NC}  $FAIL"
if [[ $SKIP -gt 0 ]]; then
    echo -e "  ${YELLOW}Skipped:${NC} $SKIP"
fi
echo -e "  ${BOLD}Summary: ${PASS}/${TOTAL} passed${NC}${SKIP:+, ${SKIP} skipped}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

# Exit with failure if any checks failed
[[ $FAIL -eq 0 ]]
