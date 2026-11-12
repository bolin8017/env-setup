#!/usr/bin/env bash
# Status line render throttle (deployed by env-setup's 08-ClaudeCode module on Windows).
#
# Claude Code re-runs the statusLine command on every conversation event (300 ms
# debounce) and cancels a render that is still running when the next event arrives
# (https://code.claude.com/docs/en/statusline, "When the status line updates"). On
# Windows one ccstatusline render is bash + node + conhost and takes seconds on a busy
# machine, so renders pile up. Measured on a dev box with seven active sessions: 160
# renders in 5 minutes, a quarter of them killed before they finished, 6.8% of all CPU.
#
# This script answers at once with the line rendered last time and starts a fresh
# render in the background at most once every MIN_INTERVAL seconds per session, so the
# line is never older than that plus one event. The docs recommend the same shape
# ("Cache expensive operations", keyed by session_id). Only bash builtins run when the
# cached line is still fresh: no process is started.
#
# usage: . statusline-throttle.sh <renderer> [args...]    (stdin: the statusLine JSON)
# Sourced from the `bash -c` Claude Code already starts, so the throttle itself adds no
# process; running it with `bash statusline-throttle.sh ...` works too.

MIN_INTERVAL=60

IFS= read -r -d '' input || true
if [[ $# -eq 0 ]]; then
    echo "statusline-throttle: no renderer given"
    exit 0
fi
# bash < 5 has no EPOCHSECONDS; without a clock there is nothing to throttle on.
if [[ -z ${EPOCHSECONDS:-} ]]; then
    exec "$@" <<<"$input"
fi

sid=default
if [[ $input =~ \"session_id\"[[:space:]]*:[[:space:]]*\"([A-Za-z0-9_-]+)\" ]]; then
    sid=${BASH_REMATCH[1]}
fi
dir=${XDG_CACHE_HOME:-$HOME/.cache}/ccstatusline-throttle
if [[ ! -d $dir ]] && ! mkdir -p "$dir" 2>/dev/null; then
    exec "$@" <<<"$input"
fi
out=$dir/$sid.out
stamp=$dir/$sid.stamp

render() {
    # Run the renderer on the saved input; keep its output only if it printed something.
    local text
    "$@" <<<"$input" >"$out.new" 2>/dev/null || return 1
    [[ -s $out.new ]] || return 1
    IFS= read -r -d '' text <"$out.new" || true
    printf '%s' "$text" >"$out"
}

prune() {
    # Drop the cache of sessions not rendered for a week. A stamp holds the epoch second
    # of the last refresh, so its age is known without starting a process.
    local f last stale=()
    for f in "$dir"/*.stamp; do
        [[ -r $f ]] || continue
        last=
        read -r last <"$f" || true      # a stamp has no trailing newline, so read returns 1
        [[ $last =~ ^[0-9]+$ ]] || continue
        if (( EPOCHSECONDS - last > 604800 )); then
            stale+=("$f" "${f%.stamp}.out" "${f%.stamp}.out.new")
        fi
    done
    if (( ${#stale[@]} )); then
        rm -f "${stale[@]}"
    fi
    return 0
}

if [[ ! -s $out ]]; then
    # First render of this session: nothing to show yet, so wait for it.
    printf '%s' "$EPOCHSECONDS" >"$stamp"
    if render "$@"; then
        IFS= read -r -d '' text <"$out" || true
        printf '%s' "$text"
    else
        "$@" <<<"$input"
    fi
    exit 0
fi

IFS= read -r -d '' text <"$out" || true
printf '%s' "$text"

last=0
if [[ -r $stamp ]]; then
    read -r last <"$stamp" || true
fi
[[ $last =~ ^[0-9]+$ ]] || last=0
if (( EPOCHSECONDS - last >= MIN_INTERVAL )); then
    # Claim the refresh before starting it: a render that gets killed half-way is tried
    # again after the interval, not on every event.
    printf '%s' "$EPOCHSECONDS" >"$stamp"
    { render "$@"; prune; } </dev/null >/dev/null 2>&1 &
    disown
fi
exit 0
