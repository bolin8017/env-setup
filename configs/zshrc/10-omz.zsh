# ================================================================
# Oh My Zsh Configuration
# ================================================================

# Path to oh-my-zsh installation
export ZSH="$HOME/.oh-my-zsh"

# Theme
ZSH_THEME="powerlevel10k/powerlevel10k"

# Update settings
zstyle ':omz:update' mode auto
zstyle ':omz:update' frequency 7

# Display red dots whilst waiting for completion
COMPLETION_WAITING_DOTS="true"

# ---------------------------
# Plugins
# ---------------------------

plugins=(
    # --- Built-in: core ---
    git
    web-search
    extract

    # --- Built-in: quality-of-life ---
    sudo
    colored-man-pages
    command-not-found
    copybuffer
    copypath
    dirhistory
    safe-paste

    # --- Built-in: tooling completions ---
    docker
    docker-compose
    gh
    fzf

    # --- External: must come BEFORE zsh-autosuggestions and zsh-syntax-highlighting ---
    fzf-tab
    zsh-completions
    zsh-you-should-use
    zsh-autosuggestions

    # zsh-syntax-highlighting MUST be the last plugin loaded
    zsh-syntax-highlighting

    # history-substring-search must come AFTER zsh-syntax-highlighting
    history-substring-search
)

# Load Oh My Zsh
source "$ZSH/oh-my-zsh.sh"
