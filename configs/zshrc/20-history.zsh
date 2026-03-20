# ================================================================
# History Configuration
# ================================================================

HISTSIZE=50000
SAVEHIST=50000
HISTFILE=~/.zsh_history

# Share history between terminals
setopt SHARE_HISTORY

# Append to history file
setopt APPEND_HISTORY

# Don't record duplicate commands
setopt HIST_IGNORE_DUPS
setopt HIST_IGNORE_ALL_DUPS

# Remove superfluous blanks
setopt HIST_REDUCE_BLANKS

# Don't store commands that start with a space
setopt HIST_IGNORE_SPACE
