#!/usr/bin/env bash
# run_e2e.sh — End-to-end test inside a Docker container
# Runs the full installer, then verifies every tool was installed correctly.
set -uo pipefail

RED=$'\033[0;31m'
GREEN=$'\033[0;32m'
CYAN=$'\033[0;36m'
BOLD=$'\033[1m'
NC=$'\033[0m'

PASS=0
FAIL=0

check() {
    local desc="$1"
    shift
    if "$@" &>/dev/null; then
        echo -e "  ${GREEN}PASS${NC}  $desc"
        (( PASS += 1 ))
    else
        echo -e "  ${RED}FAIL${NC}  $desc"
        (( FAIL += 1 ))
    fi
}

echo ""
echo -e "${CYAN}╔═══════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║${NC}  ${BOLD}env-setup — E2E Test (Ubuntu)${NC}                            ${CYAN}║${NC}"
echo -e "${CYAN}╚═══════════════════════════════════════════════════════════╝${NC}"
echo ""

# =============================================================================
# Phase 1: Run the installer
# =============================================================================
echo -e "${BOLD}Phase 1: Full Installation${NC}"
echo ""

if bash setup.sh --auto-yes 2>&1 | tee /tmp/e2e-install.log; then
    echo ""
    echo -e "  ${GREEN}Installation completed successfully${NC}"
else
    echo ""
    echo -e "  ${RED}Installation exited with non-zero status (may be partial)${NC}"
fi
echo ""

# =============================================================================
# Phase 2: Source tool paths (same as verify.sh)
# =============================================================================

# Homebrew (won't exist on Linux container, that's fine)
[[ -f "/opt/homebrew/bin/brew" ]] && eval "$(/opt/homebrew/bin/brew shellenv)" 2>/dev/null
[[ -f "/usr/local/bin/brew" ]] && eval "$(/usr/local/bin/brew shellenv)" 2>/dev/null

# Refresh command hash table after installation
hash -r 2>/dev/null || true

# nvm
export NVM_DIR="${NVM_DIR:-$HOME/.nvm}"
# shellcheck source=/dev/null
[[ -s "$NVM_DIR/nvm.sh" ]] && source "$NVM_DIR/nvm.sh" 2>/dev/null

# pyenv
export PYENV_ROOT="${PYENV_ROOT:-$HOME/.pyenv}"
export PATH="$PYENV_ROOT/bin:$PYENV_ROOT/shims:$PATH"
command -v pyenv &>/dev/null && eval "$(pyenv init --path)" 2>/dev/null

# Local bin
export PATH="$HOME/.local/bin:$PATH"

# Conda
# shellcheck source=/dev/null
[[ -f "$HOME/miniconda3/etc/profile.d/conda.sh" ]] && source "$HOME/miniconda3/etc/profile.d/conda.sh" 2>/dev/null

# =============================================================================
# Phase 3: Verify tools
# =============================================================================
echo -e "${BOLD}Phase 2: Verification${NC}"
echo ""

echo -e "${CYAN}--- Core ---${NC}"
check "git installed"                command -v git
check "gh (GitHub CLI) installed"    command -v gh
check "gcc installed"                command -v gcc
check "make installed"               command -v make
check "cmake installed"              command -v cmake

echo ""
echo -e "${CYAN}--- Languages ---${NC}"
check "nvm installed"                command -v nvm
check "node installed"               command -v node
check "npm installed"                command -v npm
check "pyenv installed"              command -v pyenv
check "python3 installed"            command -v python3

echo ""
echo -e "${CYAN}--- Python Tools ---${NC}"
check "jupyter installed"            command -v jupyter
check "poetry installed"             command -v poetry
check "uv installed"                 command -v uv

echo ""
echo -e "${CYAN}--- Docker ---${NC}"
check "docker installed"             command -v docker

echo ""
echo -e "${CYAN}--- CLI Tools ---${NC}"
check "fzf installed"                command -v fzf
check "rg (ripgrep) installed"       bash -c 'command -v rg || command -v rg'
check "bat installed"                bash -c 'command -v bat || command -v batcat'
check "jq installed"                 command -v jq
check "fd installed"                 bash -c 'command -v fd || command -v fdfind'
check "eza installed"                command -v eza
check "btop installed"               command -v btop
check "tldr installed"               command -v tldr
check "tree installed"               command -v tree
check "httpie installed"             bash -c 'command -v http || command -v https'
check "zoxide installed"             command -v zoxide

echo ""
echo -e "${CYAN}--- Shell ---${NC}"
check "zsh installed"                command -v zsh
check "Oh My Zsh dir exists"         test -d "$HOME/.oh-my-zsh"
check "Powerlevel10k dir exists"     test -d "${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/themes/powerlevel10k"
check "zsh-autosuggestions"          test -d "${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins/zsh-autosuggestions"
check "zsh-syntax-highlighting"      test -d "${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins/zsh-syntax-highlighting"
check "zsh-completions"              test -d "${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins/zsh-completions"

echo ""
echo -e "${CYAN}--- Shell Config ---${NC}"
check "~/.zshrc exists"              test -f "$HOME/.zshrc"
check "fragments dir exists"         test -d "$HOME/.config/zsh/fragments"
check "aliases.zsh deployed"         test -f "$HOME/.config/zsh/aliases.zsh"
check "~/.p10k.zsh deployed"         test -f "$HOME/.p10k.zsh"

echo ""
echo -e "${CYAN}--- Tmux ---${NC}"
check "tmux installed"               command -v tmux
check "~/.tmux.conf exists"          test -f "$HOME/.tmux.conf"
check "TPM dir exists"               test -d "$HOME/.tmux/plugins/tpm"

echo ""
echo -e "${CYAN}--- Fragment System ---${NC}"
check "00-p10k-instant-prompt"       test -f "$HOME/.config/zsh/fragments/00-p10k-instant-prompt.zsh"
check "10-omz.zsh"                   test -f "$HOME/.config/zsh/fragments/10-omz.zsh"
check "20-history.zsh"               test -f "$HOME/.config/zsh/fragments/20-history.zsh"
check "50-tools.zsh"                 test -f "$HOME/.config/zsh/fragments/50-tools.zsh"
check "15-pyenv.zsh (dynamic)"       test -f "$HOME/.config/zsh/fragments/15-pyenv.zsh"
check "16-nvm.zsh (dynamic)"         test -f "$HOME/.config/zsh/fragments/16-nvm.zsh"

# =============================================================================
# Summary
# =============================================================================
TOTAL=$(( PASS + FAIL ))
echo ""
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "  ${GREEN}Passed:${NC}  $PASS"
echo -e "  ${RED}Failed:${NC}  $FAIL"
echo -e "  ${BOLD}Total:   ${PASS}/${TOTAL}${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

if [[ $FAIL -eq 0 ]]; then
    echo -e "  ${GREEN}${BOLD}ALL E2E TESTS PASSED${NC}"
else
    echo -e "  ${RED}${BOLD}${FAIL} E2E TESTS FAILED${NC}"
    echo ""
    echo "  Full install log: /tmp/e2e-install.log"
fi
echo ""

[[ $FAIL -eq 0 ]]
