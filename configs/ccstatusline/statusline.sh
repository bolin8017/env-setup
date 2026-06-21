#!/usr/bin/env bash
# ccstatusline launcher (deployed by env-setup's 08-claude-code module).
#
# Claude Code runs the statusLine command in a NON-interactive shell. On hosts
# where env-setup installs Node via nvm with lazy-loading (which only wires
# node/npm/npx into interactive zsh, and only after the first call), those
# binaries are absent from the non-interactive PATH — so a bare
# `npx -y ccstatusline@latest` exits 127 and the status line silently stays
# blank. This launcher guarantees a node runtime is on PATH before handing off.
#
# Cross-engine note: the shared configs/claude/settings.json keeps the portable
# `npx -y ccstatusline@latest` command for the Windows engine (where node is on
# PATH via scoop/winget). Only the Unix engine repoints statusLine at this file.

# If node already resolves (system install, eager nvm, etc.), change nothing.
if ! command -v node >/dev/null 2>&1; then
    # Prepend the newest nvm-managed node bin. nvm.sh stays unsourced (fast);
    # we only need the real binaries on PATH, not nvm's shell function.
    _nb="$(ls -d "${NVM_DIR:-$HOME/.nvm}"/versions/node/*/bin 2>/dev/null | sort -V | tail -1)"
    [ -n "$_nb" ] && export PATH="$_nb:$PATH"
    unset _nb
fi

exec npx -y ccstatusline@latest
