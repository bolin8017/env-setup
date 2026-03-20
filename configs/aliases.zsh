# ================================================================
# Custom Aliases Configuration
# ================================================================

# ---------------------------
# File Operations
# ---------------------------

# List files with human-readable sizes
alias lm='ls -lh'

# List files sorted by modification time (newest first)
alias lt='ls -lht'

# Recursively grep with color and line numbers
alias grep='grep --color=auto -n'

# Count files in current directory (non-recursive)
alias filecount='ls -1 | wc -l'

# Enhanced ls (if eza is installed, otherwise fallback to ls)
if command -v eza &> /dev/null; then
    alias ll='eza -la --icons --git'
    alias lt='eza -la --icons --git --sort=modified'
    alias tree='eza --tree --icons'
else
    alias ll='ls -lAh'
fi

# ---------------------------
# Directory Navigation
# ---------------------------

# Easier navigation
alias ..='cd ..'
alias ...='cd ../..'
alias ....='cd ../../..'

# Go back to previous directory
alias -- -='cd -'

# ---------------------------
# Disk Usage
# ---------------------------

# Disk free with human-readable sizes
alias dfh='df -h'

# Disk usage of current directory
alias duh='du -h -d 1 | sort -hr'

# ---------------------------
# Process Management
# ---------------------------

# Repeat last command (useful for re-running commands)
alias rp='fc -s'

# ---------------------------
# System Operations
# ---------------------------

# Clear screen and scrollback
alias clear='clear && printf "\e[3J"'

# Reload zsh configuration
alias reload='source ~/.zshrc'

# ---------------------------
# Git Shortcuts
# ---------------------------

alias gs='git status'
alias ga='git add'
alias gc='git commit'
alias gp='git push'
alias gl='git pull'
alias gd='git diff'
alias gco='git checkout'
alias gb='git branch'
alias glog='git log --oneline --graph --decorate'

# ---------------------------
# Modern CLI Tools
# ---------------------------

# bat (better cat)
if command -v bat &> /dev/null; then
    alias cat='bat --paging=never'
    alias ccat='/bin/cat'  # Original cat
elif command -v batcat &> /dev/null; then
    alias cat='batcat --paging=never'
    alias ccat='/bin/cat'
fi

# ripgrep (better grep)
if command -v rg &> /dev/null; then
    alias rgrep='rg'
fi

# fd (better find)
if command -v fd &> /dev/null; then
    alias ffind='fd'
elif command -v fdfind &> /dev/null; then
    alias ffind='fdfind'
fi

# ---------------------------
# Development
# ---------------------------

# Python
alias py='python3'
alias pip='pip3'

# Virtual environment
alias venv='python3 -m venv'
alias activate='source venv/bin/activate'

# Quick HTTP server
alias serve='python3 -m http.server'

# ---------------------------
# Safety Aliases
# ---------------------------

# Confirm before overwriting
alias cp='cp -i'
alias mv='mv -i'
alias rm='rm -i'

# ---------------------------
# Miscellaneous
# ---------------------------

# Get public IP
alias myip='curl -s https://api.ipify.org && echo'

# Get local IP
alias localip="ifconfig | grep 'inet ' | grep -v 127.0.0.1 | awk '{print \$2}'"

# Update system (OS-specific)
if [[ "$OSTYPE" == "darwin"* ]]; then
    alias update='brew update && brew upgrade'
elif [[ -f /etc/debian_version ]]; then
    alias update='sudo apt update && sudo apt upgrade -y'
fi
