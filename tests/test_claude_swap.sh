#!/usr/bin/env bash
# test_claude_swap.sh — Functional tests for scripts/claude-swap.sh
# (credential check-in/check-out between ~/.claude and profile dirs).
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

source "$SCRIPT_DIR/test_framework.sh"

# test_framework.sh enables `set -e`; this suite deliberately runs the swap
# script in ways that must fail (unknown profile, bad name, macOS guard).
set +e

SWAP="$PROJECT_ROOT/scripts/claude-swap.sh"

echo -e "${_T_BOLD}Test: claude-swap credential check-out${_T_NC}"

if ! command -v jq >/dev/null 2>&1; then
    echo "SKIP: jq not installed — claude-swap tests need jq"
    exit 0
fi

# Fresh fake HOME per suite; two accounts: default (A) and profile louis (B).
_setup_home() {
    _H="$TEST_TMPDIR/swap_home_$RANDOM"
    mkdir -p "$_H/.claude" "$_H/.claude-louis"
    printf '%s' '{"claudeAiOauth":{"accessToken":"TOKEN_A","refreshToken":"REFRESH_A","expiresAt":1}}' \
        > "$_H/.claude/.credentials.json"
    printf '%s' '{"oauthAccount":{"emailAddress":"a@x.com"},"userID":"uA","theme":"dark"}' \
        > "$_H/.claude.json"
    printf '%s' '{"claudeAiOauth":{"accessToken":"TOKEN_B","refreshToken":"REFRESH_B","expiresAt":2}}' \
        > "$_H/.claude-louis/.credentials.json"
    printf '%s' '{"oauthAccount":{"emailAddress":"b@x.com"},"userID":"uB"}' \
        > "$_H/.claude-louis/.claude.json"
}

# =============================================================================
suite "swap default -> profile"
# =============================================================================

_setup_home
_out="$(HOME="$_H" bash "$SWAP" louis 2>&1)"
_rc=$?
assert_eq "0" "$_rc" "swap to louis exits 0"

assert_contains "$(cat "$_H/.claude/.credentials.json")" "TOKEN_B" \
    "live credential is now louis's"
assert_file_exists "$_H/.claude/.credential-stash/default.credentials.json" \
    "default credential stashed"
assert_contains "$(cat "$_H/.claude/.credential-stash/default.credentials.json")" "TOKEN_A" \
    "stash holds the default credential"
assert_eq "louis" "$(cat "$_H/.claude/.credential-owner")" "owner marker says louis"
assert_eq "b@x.com" "$(jq -r '.oauthAccount.emailAddress' "$_H/.claude.json")" \
    "identity in ~/.claude.json follows the swap"
assert_eq "dark" "$(jq -r '.theme' "$_H/.claude.json")" \
    "unrelated state in ~/.claude.json survives"

# =============================================================================
suite "swap back writes the freshest copy home (rotation safety)"
# =============================================================================

# Simulate the CLI refreshing louis's token while checked out: live file changes.
printf '%s' '{"claudeAiOauth":{"accessToken":"TOKEN_B2","refreshToken":"REFRESH_B2","expiresAt":3}}' \
    > "$_H/.claude/.credentials.json"

_out="$(HOME="$_H" bash "$SWAP" default 2>&1)"
assert_eq "0" "$?" "swap back to default exits 0"

assert_contains "$(cat "$_H/.claude-louis/.credentials.json")" "REFRESH_B2" \
    "refreshed louis credential written back to its home (not the stale copy)"
assert_contains "$(cat "$_H/.claude/.credentials.json")" "TOKEN_A" \
    "live credential is the default again"
assert_eq "default" "$(cat "$_H/.claude/.credential-owner")" "owner marker back to default"
assert_eq "a@x.com" "$(jq -r '.oauthAccount.emailAddress' "$_H/.claude.json")" \
    "identity restored to the default account"

# =============================================================================
suite "guard rails"
# =============================================================================

_setup_home
_out="$(HOME="$_H" bash "$SWAP" louis 2>&1)"
_out="$(HOME="$_H" bash "$SWAP" louis 2>&1)"
assert_eq "0" "$?" "swapping to the current owner is a no-op success"
assert_contains "$_out" "already" "no-op says already using"

_out="$(HOME="$_H" bash "$SWAP" nosuch 2>&1)"
[[ $? -ne 0 ]]
assert_true $? "unknown profile fails"
assert_contains "$_out" "claude-as nosuch" "error tells how to capture the credential once"

_out="$(HOME="$_H" bash "$SWAP" 'bad/name' 2>&1)"
[[ $? -ne 0 ]]
assert_true $? "path-like profile name is rejected"

_out="$(HOME="$_H" bash "$SWAP" 2>&1)"
[[ $? -ne 0 ]]
assert_true $? "no argument fails with usage"
assert_contains "$_out" "usage" "usage printed"

# =============================================================================
suite "--status"
# =============================================================================

_setup_home
_out="$(HOME="$_H" bash "$SWAP" --status 2>&1)"
assert_eq "0" "$?" "--status exits 0"
assert_contains "$_out" "default" "status names the current owner"
assert_contains "$_out" "louis" "status lists available profiles"

# =============================================================================
suite "macOS guard"
# =============================================================================

# Shim uname so the script believes it is on Darwin (Keychain territory).
_shim="$TEST_TMPDIR/swap_shim"
mkdir -p "$_shim"
printf '#!/usr/bin/env bash\necho Darwin\n' > "$_shim/uname"
chmod +x "$_shim/uname"
_setup_home
_out="$(HOME="$_H" PATH="$_shim:$PATH" bash "$SWAP" louis 2>&1)"
[[ $? -ne 0 ]]
assert_true $? "refuses on macOS (Keychain-stored default credential)"
assert_contains "$_out" "Keychain" "macOS error mentions the Keychain"

print_test_summary
