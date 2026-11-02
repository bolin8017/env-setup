#!/usr/bin/env bash
# ccstatusline launcher (deployed by env-setup's 08-claude-code module).
#
# Claude Code runs the statusLine command in a NON-interactive shell. On hosts
# where env-setup installs Node via nvm with lazy-loading (which only wires
# node/npm/npx into interactive zsh, and only after the first call), those
# binaries are absent from the non-interactive PATH — so a bare `node` exits
# 127 and the status line silently stays blank. This launcher guarantees a
# node runtime is on PATH before handing off.
#
# It runs the copy 08-claude-code installed at the pinned version, never
# `npx`: Claude Code cancels a status line command that is still running when
# the next refresh fires, and npx's npm startup plus registry lookup can
# outlast the refreshInterval, so the line would never render.

# If node already resolves (system install, eager nvm, etc.), change nothing.
if ! command -v node >/dev/null 2>&1; then
    # Prepend the newest nvm-managed node bin. nvm.sh stays unsourced (fast);
    # we only need the real binaries on PATH, not nvm's shell function.
    _nb="$(ls -d "${NVM_DIR:-$HOME/.nvm}"/versions/node/*/bin 2>/dev/null | sort -V | tail -1)"
    [ -n "$_nb" ] && export PATH="$_nb:$PATH"
    unset _nb
fi

_entry="$HOME/.local/share/ccstatusline/node_modules/ccstatusline/dist/ccstatusline.js"
if [ -f "$_entry" ]; then
    exec node "$_entry"
fi
echo "ccstatusline not installed - re-run env-setup (08-claude-code)"
