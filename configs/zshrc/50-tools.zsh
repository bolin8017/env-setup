# ================================================================
# Modern CLI Tool Integrations
# ================================================================
# Each tool is guarded with `command -v` to avoid errors when not installed.

# ---------------------------
# fzf - Fuzzy Finder
# ---------------------------
if command -v fzf &>/dev/null; then
    # Auto-completion and key bindings
    [[ -f ~/.fzf.zsh ]] && source ~/.fzf.zsh

    # Use fd for fzf if available
    if command -v fd &>/dev/null; then
        export FZF_DEFAULT_COMMAND='fd --type f --hidden --follow --exclude .git'
        export FZF_CTRL_T_COMMAND="$FZF_DEFAULT_COMMAND"
    elif command -v fdfind &>/dev/null; then
        export FZF_DEFAULT_COMMAND='fdfind --type f --hidden --follow --exclude .git'
        export FZF_CTRL_T_COMMAND="$FZF_DEFAULT_COMMAND"
    fi

    # Enhanced fzf options
    export FZF_DEFAULT_OPTS='--height 40% --layout=reverse --border --inline-info'
else
    # Fallback: basic Ctrl+R history search
    bindkey '^R' history-incremental-search-backward
fi

# ---------------------------
# zoxide - Smarter cd
# ---------------------------
if command -v zoxide &>/dev/null; then
    eval "$(zoxide init zsh)"
fi

# ---------------------------
# bat - Better cat
# ---------------------------
if command -v bat &>/dev/null; then
    export BAT_THEME="Monokai Extended"
    export MANPAGER="sh -c 'col -bx | bat -l man -p'"
elif command -v batcat &>/dev/null; then
    export BAT_THEME="Monokai Extended"
    export MANPAGER="sh -c 'col -bx | batcat -l man -p'"
fi
