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
    # Built-in plugins
    git
    web-search
    extract

    # Custom plugins (installed separately)
    zsh-autosuggestions
    zsh-syntax-highlighting
    zsh-completions
)

# Load Oh My Zsh
source "$ZSH/oh-my-zsh.sh"
