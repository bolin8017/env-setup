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

# This list is the source of truth for what LOADS (ordering matters and is
# encoded here); config.yaml's shell.plugins.external controls what gets
# CLONED. External entries are existence-guarded below, so removing one from
# config (and uninstalling its clone) no longer leaves an OMZ "plugin not
# found" warning on every shell start.
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
)

# --- External: only when the clone exists; must come BEFORE
# zsh-autosuggestions and zsh-syntax-highlighting.
# (the extra-completions package is intentionally absent here: it is
# fpath-registered by the 05-completions-fpath.zsh fragment BEFORE
# compinit, which is the only way its src/ functions actually register.)
_envsetup_custom="${ZSH_CUSTOM:-$ZSH/custom}/plugins"
for _envsetup_p in fzf-tab zsh-you-should-use zsh-autosuggestions zsh-syntax-highlighting; do
    # zsh-syntax-highlighting MUST stay the last external loaded
    [[ -d "$_envsetup_custom/$_envsetup_p" ]] && plugins+=("$_envsetup_p")
done
unset _envsetup_custom _envsetup_p

# history-substring-search (built-in) must come AFTER zsh-syntax-highlighting
plugins+=(history-substring-search)

# Load Oh My Zsh
source "$ZSH/oh-my-zsh.sh"
