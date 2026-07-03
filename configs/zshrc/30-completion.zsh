# ================================================================
# Completion Configuration
# ================================================================

# (extra-completions fpath registration lives in 05-completions-fpath.zsh:
# compinit has already run by this point, so fpath changes here are inert.)

# Case-insensitive completion
zstyle ':completion:*' matcher-list 'm:{a-zA-Z}={A-Za-z}'

# Use menu selection for completion
zstyle ':completion:*' menu select

# Color completion
zstyle ':completion:*' list-colors "${(s.:.)LS_COLORS}"

# Speed up pasting
zstyle ':bracketed-paste-magic' active-widgets '.self-*'
