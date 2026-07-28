#!/usr/bin/env bash
# test_claude_profile_statusline.sh — Functional tests for the statusLine seed
# that `claude-as` performs on a profile config dir (configs/aliases.zsh).
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

source "$SCRIPT_DIR/test_framework.sh"

# The helper returns non-zero on its "nothing to do" paths; test_framework.sh
# turns on `set -e`, which would abort the suite on the first such call.
set +e

echo -e "${_T_BOLD}Test: claude-as profile statusLine seed${_T_NC}"

if ! command -v jq >/dev/null 2>&1; then
    echo "SKIP: jq not installed — statusLine seed tests need jq"
    exit 0
fi

# Load just the helper out of the aliases file: sourcing the whole file would
# shadow ls/cat/… for the rest of the suite.
_fn="$(awk '/^_claude_seed_profile_statusline\(\) \{/,/^\}/' "$PROJECT_ROOT/configs/aliases.zsh")"
if [[ -z "$_fn" ]]; then
    echo "FAIL: aliases.zsh does not define _claude_seed_profile_statusline" >&2
    exit 1
fi
eval "$_fn"

SL='{"type":"command","command":"/home/u/.config/ccstatusline/statusline.sh","padding":0,"refreshInterval":10}'

# Fresh fake HOME with a default config that carries a statusLine block.
_setup_home() {
    _H="$TEST_TMPDIR/sl_home_$RANDOM"
    mkdir -p "$_H/.claude"
    jq -n --argjson sl "$SL" '{theme:"dark", statusLine:$sl}' > "$_H/.claude/settings.json"
}

# =============================================================================
suite "seeds a profile that has no settings.json"
# =============================================================================

_setup_home
HOME="$_H" _claude_seed_profile_statusline "$_H/.claude-work"

assert_file_exists "$_H/.claude-work/settings.json" "profile settings.json created"
assert_eq "$(jq -Sc '.' <<<"$SL")" "$(jq -Sc '.statusLine' "$_H/.claude-work/settings.json")" \
    "statusLine copied verbatim from the default config"

# =============================================================================
suite "fills the gap without touching existing profile settings"
# =============================================================================

_setup_home
mkdir -p "$_H/.claude-work"
printf '%s' '{"theme":"light","effortLevel":"high"}' > "$_H/.claude-work/settings.json"
HOME="$_H" _claude_seed_profile_statusline "$_H/.claude-work"

assert_eq "light" "$(jq -r '.theme' "$_H/.claude-work/settings.json")" \
    "unrelated profile settings survive"
assert_eq "high" "$(jq -r '.effortLevel' "$_H/.claude-work/settings.json")" \
    "profile-only keys survive"
assert_eq "command" "$(jq -r '.statusLine.type' "$_H/.claude-work/settings.json")" \
    "statusLine added alongside them"

# =============================================================================
suite "never overwrites a profile's own statusLine"
# =============================================================================

_setup_home
mkdir -p "$_H/.claude-work"
printf '%s' '{"statusLine":{"type":"command","command":"mine"}}' > "$_H/.claude-work/settings.json"
HOME="$_H" _claude_seed_profile_statusline "$_H/.claude-work"

assert_eq "mine" "$(jq -r '.statusLine.command' "$_H/.claude-work/settings.json")" \
    "hand-picked profile statusLine is left alone"

# =============================================================================
suite "no-ops when there is nothing to copy"
# =============================================================================

_H="$TEST_TMPDIR/sl_home_none_$RANDOM"
mkdir -p "$_H/.claude"
printf '%s' '{"theme":"dark"}' > "$_H/.claude/settings.json"
HOME="$_H" _claude_seed_profile_statusline "$_H/.claude-work"
assert_file_not_exists "$_H/.claude-work/settings.json" \
    "no profile settings.json when the default config has no statusLine"

_H="$TEST_TMPDIR/sl_home_nofile_$RANDOM"
mkdir -p "$_H"
HOME="$_H" _claude_seed_profile_statusline "$_H/.claude-work"
assert_file_not_exists "$_H/.claude-work/settings.json" \
    "no profile settings.json when the default config is missing"

# =============================================================================
suite "refuses to guess on a malformed profile settings.json"
# =============================================================================

_setup_home
mkdir -p "$_H/.claude-work"
printf '%s' '{not json' > "$_H/.claude-work/settings.json"
HOME="$_H" _claude_seed_profile_statusline "$_H/.claude-work"

assert_eq '{not json' "$(cat "$_H/.claude-work/settings.json")" \
    "malformed profile settings.json left untouched"

# =============================================================================
suite "claude-as wires the seed in"
# =============================================================================

aliases_content="$(cat "$PROJECT_ROOT/configs/aliases.zsh")"
assert_contains "$aliases_content" "_claude_seed_profile_statusline \"\$HOME/.claude-\$profile\"" \
    "claude-as seeds the profile before launching claude"

print_test_summary
