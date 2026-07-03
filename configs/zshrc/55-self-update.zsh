# ================================================================
# env-setup self-update check (oh-my-zsh-style cadence gate)
# ================================================================
# Reads ~/.env-setup/update.env (written by the shell module at install time).
# On a new interactive shell, at most once per ENVSETUP_UPDATE_FREQ_DAYS:
# git fetch; if behind upstream, pull --ff-only and offer to re-run setup.
# Self-contained; every git op soft-fails and never breaks the shell.

_envsetup_state_file="${HOME}/.env-setup/update.env"
[[ -r "$_envsetup_state_file" ]] && source "$_envsetup_state_file"
unset _envsetup_state_file

# _envsetup_should_check <last_epoch> <now_epoch> <freq_days> -> 0 (true) if due
_envsetup_should_check() {
    local last="$1" now="$2" freq="$3"
    [[ "$freq" == <-> ]] || freq=7          # zsh numeric glob; fallback if junk
    (( freq == 0 )) && return 0             # 0 = check every shell
    [[ "$last" == <-> ]] || return 0        # missing/invalid stamp -> due
    (( now - last >= freq * 86400 ))
}

_envsetup_update_check() {
    [[ "${ENVSETUP_UPDATE_ENABLED:-0}" == "1" ]] || return 0
    [[ -o interactive ]] || return 0
    command -v git &>/dev/null || return 0
    local repo="${ENVSETUP_REPO_DIR:-}"
    [[ -n "$repo" && -d "$repo/.git" ]] || return 0

    local stamp="${HOME}/.env-setup/.update-last-check"
    local now last
    now="$(date +%s)"
    last="$(cat "$stamp" 2>/dev/null || echo 0)"
    _envsetup_should_check "$last" "$now" "${ENVSETUP_UPDATE_FREQ_DAYS:-7}" || return 0

    # Stamp up-front so a failing fetch doesn't retry on every shell.
    echo "$now" > "$stamp" 2>/dev/null

    # GIT_TERMINAL_PROMPT=0 / BatchMode: with stderr discarded, a credential
    # prompt (expired HTTPS token, passphrased SSH key) would be invisible
    # while git waits on stdin — the new shell looks frozen. Fail fast instead.
    GIT_TERMINAL_PROMPT=0 GIT_SSH_COMMAND='ssh -oBatchMode=yes' \
        git -C "$repo" fetch --quiet 2>/dev/null || return 0
    local behind
    behind="$(git -C "$repo" rev-list --count HEAD..@{u} 2>/dev/null || echo 0)"
    [[ "$behind" == <-> && "$behind" -gt 0 ]] || return 0

    if ! GIT_TERMINAL_PROMPT=0 git -C "$repo" pull --ff-only --quiet 2>/dev/null; then
        print -P "%F{yellow}env-setup: update available but fast-forward failed; resolve ${repo} by hand.%f"
        return 0
    fi

    # No interactive prompt here: during zshrc init the p10k instant prompt
    # buffers output, so a read would eat keystrokes against an invisible
    # question. Print the notice and let the user apply when convenient.
    print -P "%F{cyan}env-setup updated (${behind} new commit(s)). Run %F{green}env-update%f%F{cyan} to apply.%f"
}

# Don't recurse while a triggered setup re-run is in progress.
[[ -z "${ENVSETUP_UPDATE_RUNNING:-}" ]] && _envsetup_update_check
