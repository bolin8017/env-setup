#!/usr/bin/env bash
# claude-swap — check a different account's credential into ~/.claude.
#
# Claude Code's OAuth refresh tokens rotate and are single-use: whichever
# copy of a credential refreshes last is the only valid one, and using a
# stale copy can invalidate the whole token family (forcing /login on every
# copy). So this script never duplicates a credential — it MOVES ownership:
# the live file's freshest copy is always written back to its home before
# another account's credential is checked in. The current occupant of
# ~/.claude is recorded in .credential-owner; the default account's
# credential parks in .credential-stash/ while a profile is checked out.
#
# usage: claude-swap <profile>|default|--status
set -euo pipefail

CLAUDE_DIR="${HOME}/.claude"
LIVE="${CLAUDE_DIR}/.credentials.json"
MARKER="${CLAUDE_DIR}/.credential-owner"
STASH="${CLAUDE_DIR}/.credential-stash"
STATE_JSON="${HOME}/.claude.json"

err() { echo "claude-swap: $*" >&2; exit 1; }

usage() { echo "usage: claude-swap <profile>|default|--status"; }

# Credential home for an owner label ("default" parks in the stash).
_home_of() {
    if [[ "$1" == "default" ]]; then
        echo "${STASH}/default.credentials.json"
    else
        echo "${HOME}/.claude-$1/.credentials.json"
    fi
}

# Where an owner's account identity (oauthAccount/userID) can be read from.
_identity_of() {
    if [[ "$1" == "default" ]]; then
        echo "${STASH}/default.identity.json"
    else
        echo "${HOME}/.claude-$1/.claude.json"
    fi
}

[[ "$(uname -s)" == Darwin ]] && err \
    "macOS stores the default-account credential in the Keychain — file swap does not apply; use /login inside claude instead."

command -v jq >/dev/null 2>&1 || err "jq is required"

target="${1:-}"
[[ -z "$target" ]] && { usage >&2; exit 2; }

cur="default"
[[ -f "$MARKER" ]] && cur="$(cat "$MARKER")"

if [[ "$target" == "--status" ]]; then
    echo "current ~/.claude credential owner: ${cur}"
    if [[ -f "$LIVE" ]]; then
        exp="$(jq -r '.claudeAiOauth.expiresAt // empty' "$LIVE" 2>/dev/null || true)"
        [[ -n "$exp" ]] && echo "live access token expiresAt: ${exp} (epoch ms; CLI auto-refreshes)"
    fi
    echo "available to swap:"
    [[ "$cur" != "default" && -f "$(_home_of default)" ]] && echo "  - default"
    shopt -s nullglob
    for d in "${HOME}"/.claude-*/; do
        name="$(basename "$d")"; name="${name#.claude-}"
        [[ "$name" == "$cur" ]] && continue
        [[ -f "${d}.credentials.json" ]] && echo "  - ${name}"
    done
    shopt -u nullglob
    exit 0
fi

if [[ "$target" == "$cur" ]]; then
    echo "already using the '${target}' credential — nothing to do"
    exit 0
fi

if [[ "$target" != "default" ]]; then
    [[ "$target" =~ ^[A-Za-z0-9_-]+$ ]] || err "invalid profile name '${target}' (use letters/digits/-/_)"
    [[ -f "$(_home_of "$target")" ]] || err \
        "no stored credential for '${target}' — capture it once with: claude-as ${target} then /login"
else
    [[ -f "$(_home_of default)" ]] || err "no stashed default credential to restore"
fi

[[ -f "$LIVE" ]] || err "no live credential at ${LIVE} — log in first"

mkdir -p "$STASH"
chmod 700 "$STASH" 2>/dev/null || true

# Freshness warning: a credential that has not been refreshed for a week may
# hold an expired refresh token; a failed refresh with a stale token is what
# kills token families.
tfile="$(_home_of "$target")"
if [[ -n "$(find "$tfile" -mtime +7 2>/dev/null)" ]]; then
    echo "warning: '${target}' credential was last refreshed more than 7 days ago;" \
         "if requests fail after the swap, log that account in once again."
fi

# 1. Write the live (freshest) credential back to the current owner's home.
cp -p "$LIVE" "$(_home_of "$cur")"
if [[ "$cur" == "default" && -f "$STATE_JSON" ]]; then
    jq '{oauthAccount: (.oauthAccount // null), userID: (.userID // null)}' \
        "$STATE_JSON" > "$(_identity_of default)" 2>/dev/null || true
fi

# 2. Check the target credential in.
cp -p "$tfile" "$LIVE"

# 3. Keep ~/.claude.json's account identity truthful (what /login would do).
idsrc="$(_identity_of "$target")"
if [[ -f "$idsrc" && -f "$STATE_JSON" ]]; then
    id_json="$(jq -c '{oauthAccount: (.oauthAccount // null), userID: (.userID // null)} | with_entries(select(.value != null))' "$idsrc" 2>/dev/null || echo '{}')"
    if [[ "$id_json" != "{}" ]]; then
        tmp="${STATE_JSON}.tmp.$$"
        if jq --argjson id "$id_json" '. + $id' "$STATE_JSON" > "$tmp" 2>/dev/null; then
            mv "$tmp" "$STATE_JSON"
        else
            rm -f "$tmp"
            echo "warning: could not update account identity in ~/.claude.json (cosmetic only)"
        fi
    fi
fi

# 4. Record the new owner.
echo "$target" > "$MARKER"

echo "swapped ~/.claude credential: ${cur} -> ${target}"
echo "running sessions may keep using the old token from memory; if the next"
echo "replies still act as '${cur}', exit and resume with: claude -c"
echo "while '${target}' is checked out here, do NOT run: claude-as ${target}"
echo "swap back with: claude-swap ${cur}"
