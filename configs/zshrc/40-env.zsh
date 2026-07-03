# ================================================================
# Environment Variables
# ================================================================

# Preferred editor — guarded: this repo doesn't install vim, and an EDITOR
# pointing at a missing binary breaks `git commit` on minimal systems.
if command -v vim >/dev/null 2>&1; then
    export EDITOR='vim' VISUAL='vim'
elif command -v vi >/dev/null 2>&1; then
    export EDITOR='vi' VISUAL='vi'
fi

# Language environment. LANG only, and only when the locale exists: minimal
# Debian/WSL images often lack en_US.UTF-8 (setlocale warnings on every
# command), and forcing the whole locale family would clobber user LC_*.
if command -v locale >/dev/null 2>&1     && locale -a 2>/dev/null | grep -qiE '^en_US\.(UTF-8|utf8)$'; then
    export LANG=en_US.UTF-8
fi

# PATH additions (guarded against duplication in nested shells: tmux/zellij
# panes source .zshrc again with the entry already present)
if [[ -d "${HOME}/.local/bin" && ":$PATH:" != *":${HOME}/.local/bin:"* ]]; then
    export PATH="${HOME}/.local/bin:${PATH}"
fi

# Directory navigation options
setopt AUTO_CD
setopt AUTO_PUSHD
setopt PUSHD_IGNORE_DUPS
setopt PUSHD_SILENT

# Note: pyenv/nvm/conda/homebrew init are generated dynamically by their modules
