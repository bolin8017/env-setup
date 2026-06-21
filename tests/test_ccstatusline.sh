#!/usr/bin/env bash
# test_ccstatusline.sh — Tests for 08-claude-code.sh ccstatusline integration
# and the broader ~/.claude/settings.json whitelist merge.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

source "$SCRIPT_DIR/test_framework.sh"
source "$PROJECT_ROOT/lib/common.sh"
source "$PROJECT_ROOT/lib/yaml.sh"
source "$PROJECT_ROOT/lib/dryrun.sh"
source "$PROJECT_ROOT/lib/config.sh"

_setup_tmpdir
setup_logging
load_config "$PROJECT_ROOT/config.yaml"
DRY_RUN="false"
AUTO_YES="true"
export ENV_SETUP_DIR="$PROJECT_ROOT"

# Re-point HOME at the test tmp dir so we never touch the real $HOME
ORIG_HOME="$HOME"
export HOME="$TEST_TMPDIR"
mkdir -p "$HOME/.config" "$HOME/.claude"

# shellcheck source=/dev/null
source "$PROJECT_ROOT/modules/08-claude-code.sh"

echo -e "${_T_BOLD}Test: 08-claude-code.sh ccstatusline + settings merge${_T_NC}"

# Reset target paths between suites
_reset() {
    rm -rf "$HOME/.config/ccstatusline"
    rm -f "$HOME/.claude/settings.json" "$HOME/.claude/settings.json".bak.*
}

# ---------------------------------------------------------------------------
suite "Template snapshot exists and parses"
# ---------------------------------------------------------------------------
assert_file_exists "$PROJECT_ROOT/configs/ccstatusline/settings.json" \
    "configs/ccstatusline/settings.json is in the repo"
jq empty "$PROJECT_ROOT/configs/ccstatusline/settings.json" 2>/dev/null
assert_true "$?" "ccstatusline template is valid JSON"

assert_file_exists "$PROJECT_ROOT/configs/claude/settings.json" \
    "configs/claude/settings.json is in the repo"
jq empty "$PROJECT_ROOT/configs/claude/settings.json" 2>/dev/null
assert_true "$?" "claude settings template is valid JSON"

# ---------------------------------------------------------------------------
suite "Disabled config: nothing happens"
# ---------------------------------------------------------------------------
_reset
CFG_CLAUDE_CODE_CCSTATUSLINE_ENABLED="false" \
    _install_ccstatusline >/dev/null 2>&1
assert_file_not_exists "$HOME/.config/ccstatusline/settings.json" \
    "ccstatusline widget not deployed when ccstatusline.enabled=false"

# ---------------------------------------------------------------------------
suite "Deploy: fresh install drops the template byte-identically"
# ---------------------------------------------------------------------------
_reset
_deploy_ccstatusline_config >/dev/null 2>&1
assert_file_exists "$HOME/.config/ccstatusline/settings.json" \
    "ccstatusline settings.json deployed"
diff -q "$PROJECT_ROOT/configs/ccstatusline/settings.json" \
        "$HOME/.config/ccstatusline/settings.json" >/dev/null
assert_true "$?" "deployed file is byte-identical to template"

# ---------------------------------------------------------------------------
suite "Deploy: existing file under AUTO_YES is overwritten"
# ---------------------------------------------------------------------------
mkdir -p "$HOME/.config/ccstatusline"
echo '{ "version": 0, "lines": [] }' > "$HOME/.config/ccstatusline/settings.json"
_deploy_ccstatusline_config >/dev/null 2>&1
diff -q "$PROJECT_ROOT/configs/ccstatusline/settings.json" \
        "$HOME/.config/ccstatusline/settings.json" >/dev/null
assert_true "$?" "overwrite restores template content"

# ---------------------------------------------------------------------------
suite "Merge: missing ~/.claude/settings.json creates a fresh file"
# ---------------------------------------------------------------------------
_reset
_merge_claude_settings >/dev/null 2>&1
assert_file_exists "$HOME/.claude/settings.json" "settings.json created"
jq empty "$HOME/.claude/settings.json" 2>/dev/null
assert_true "$?" "created file is valid JSON"
cmd="$(jq -r '.statusLine.command' "$HOME/.claude/settings.json")"
assert_eq "npx -y ccstatusline@latest" "$cmd" \
    "statusLine.command merged from repo template"

# ---------------------------------------------------------------------------
suite "Merge: non-whitelisted keys are preserved verbatim"
# ---------------------------------------------------------------------------
# settings_merge_keys whitelists env, statusLine, enabledPlugins,
# skipDangerousModePermissionPrompt, teammateMode. Any other top-level key
# the user has locally (experimental flags, auth, machine-specific state)
# must survive the merge untouched.
_reset
cat > "$HOME/.claude/settings.json" <<'JSON'
{
  "agentPushNotifEnabled": true,
  "someCustomKey": "preserve-me",
  "teammateMode": "in-process"
}
JSON
_merge_claude_settings >/dev/null 2>&1
assert_eq "true"        "$(jq -r '.agentPushNotifEnabled' "$HOME/.claude/settings.json")" \
    "non-whitelisted agentPushNotifEnabled preserved"
assert_eq "preserve-me" "$(jq -r '.someCustomKey'        "$HOME/.claude/settings.json")" \
    "non-whitelisted custom key preserved"
assert_eq "tmux"        "$(jq -r '.teammateMode'         "$HOME/.claude/settings.json")" \
    "whitelisted teammateMode replaced with repo value"
assert_eq "npx -y ccstatusline@latest" \
    "$(jq -r '.statusLine.command' "$HOME/.claude/settings.json")" \
    "whitelisted statusLine added from repo"

# ---------------------------------------------------------------------------
suite "Merge: idempotent — already in sync, no .bak, no content change"
# ---------------------------------------------------------------------------
_reset
# The settled, in-sync state has statusLine.command pointed at the launcher
# wrapper (see _set_ccstatusline_command), not the repo's portable npx command.
jq --arg cmd "$HOME/.config/ccstatusline/statusline.sh" \
   'if .statusLine then .statusLine.command = $cmd else . end' \
   "$PROJECT_ROOT/configs/claude/settings.json" > "$HOME/.claude/settings.json"
hash_before="$(sha256sum "$HOME/.claude/settings.json" | awk '{print $1}')"
out="$(_merge_claude_settings 2>&1)"
hash_after="$(sha256sum "$HOME/.claude/settings.json" | awk '{print $1}')"
assert_eq "$hash_before" "$hash_after" "file content unchanged on idempotent run"
assert_eq "0" "$(find "$HOME/.claude" -name 'settings.json.bak.*' 2>/dev/null | wc -l | tr -d ' ')" \
    "no .bak created for idempotent run"
assert_contains "$out" "already in sync" "logs idempotent skip"

# ---------------------------------------------------------------------------
suite "Merge: stale whitelisted value triggers .bak and update"
# ---------------------------------------------------------------------------
_reset
cat > "$HOME/.claude/settings.json" <<'JSON'
{
  "statusLine": { "type": "command", "command": "echo old", "padding": 0 }
}
JSON
_merge_claude_settings >/dev/null 2>&1
bak="$(find "$HOME/.claude" -maxdepth 1 -name 'settings.json.bak.*' | head -1)"
assert_neq "" "$bak" ".bak created when whitelisted key changes"
assert_contains "$(cat "$bak")" "echo old" "old command preserved in .bak"
assert_eq "npx -y ccstatusline@latest" \
    "$(jq -r '.statusLine.command' "$HOME/.claude/settings.json")" \
    "statusLine.command updated to repo version"

# ---------------------------------------------------------------------------
suite "Merge: jq missing → log_warn, no mutation"
# ---------------------------------------------------------------------------
_reset
cat > "$HOME/.claude/settings.json" <<'JSON'
{ "teammateMode": "in-process" }
JSON
# Override command_exists to claim jq is missing, then restore so later
# suites do not see jq as missing. shellcheck disable=SC2317 — both
# definitions are reached via indirect invocation from _merge_claude_settings.
# shellcheck disable=SC2317
command_exists() { [[ "$1" == "jq" ]] && return 1; builtin command -v "$1" &>/dev/null; }
out="$(_merge_claude_settings 2>&1)"
# shellcheck disable=SC2317
command_exists() { command -v "$1" &>/dev/null; }   # restore lib/common.sh original
assert_contains "$out" "jq" "logs warning mentioning jq"
assert_eq "in-process" "$(jq -r '.teammateMode' "$HOME/.claude/settings.json")" \
    "existing settings.json untouched when jq missing"

# ---------------------------------------------------------------------------
suite "Merge: malformed JSON → log_error, file unchanged"
# ---------------------------------------------------------------------------
_reset
echo "{ this is not json" > "$HOME/.claude/settings.json"
before="$(cat "$HOME/.claude/settings.json")"
out="$(_merge_claude_settings 2>&1)"
after="$(cat "$HOME/.claude/settings.json")"
assert_eq "$before" "$after" "malformed file preserved verbatim"
assert_contains "$out" "ERROR" "log_error emitted"

# ---------------------------------------------------------------------------
suite "Launcher wrapper: repo file exists, executable, ensures node on PATH"
# ---------------------------------------------------------------------------
assert_file_exists "$PROJECT_ROOT/configs/ccstatusline/statusline.sh" \
    "configs/ccstatusline/statusline.sh is in the repo"
[[ -x "$PROJECT_ROOT/configs/ccstatusline/statusline.sh" ]]
assert_true "$?" "launcher wrapper is executable"
wrapper_body="$(cat "$PROJECT_ROOT/configs/ccstatusline/statusline.sh")"
assert_contains "$wrapper_body" "command -v node" "wrapper checks for node on PATH"
assert_contains "$wrapper_body" "versions/node" "wrapper falls back to nvm node bin"
assert_contains "$wrapper_body" "ccstatusline@latest" "wrapper execs ccstatusline"

# ---------------------------------------------------------------------------
suite "Deploy: launcher wrapper is deployed executable"
# ---------------------------------------------------------------------------
_reset
_deploy_ccstatusline_config >/dev/null 2>&1
assert_file_exists "$HOME/.config/ccstatusline/statusline.sh" "wrapper deployed"
[[ -x "$HOME/.config/ccstatusline/statusline.sh" ]]
assert_true "$?" "deployed wrapper is executable"

# ---------------------------------------------------------------------------
suite "Repoint: _set_ccstatusline_command points statusLine at the wrapper"
# ---------------------------------------------------------------------------
_reset
_deploy_ccstatusline_config >/dev/null 2>&1
_merge_claude_settings >/dev/null 2>&1   # creates settings.json (command=npx)
assert_eq "npx -y ccstatusline@latest" \
    "$(jq -r '.statusLine.command' "$HOME/.claude/settings.json")" \
    "before repoint: command is the portable npx"
_set_ccstatusline_command >/dev/null 2>&1
assert_eq "$HOME/.config/ccstatusline/statusline.sh" \
    "$(jq -r '.statusLine.command' "$HOME/.claude/settings.json")" \
    "after repoint: command points at the launcher wrapper"
assert_eq "command" "$(jq -r '.statusLine.type' "$HOME/.claude/settings.json")" \
    "other statusLine fields (type) preserved"
hb="$(sha256sum "$HOME/.claude/settings.json" | awk '{print $1}')"
_set_ccstatusline_command >/dev/null 2>&1
ha="$(sha256sum "$HOME/.claude/settings.json" | awk '{print $1}')"
assert_eq "$hb" "$ha" "repoint is idempotent (second call is a no-op)"

# ---------------------------------------------------------------------------
suite "Repoint disabled: ccstatusline.enabled=false leaves command untouched"
# ---------------------------------------------------------------------------
_reset
_merge_claude_settings >/dev/null 2>&1
CFG_CLAUDE_CODE_CCSTATUSLINE_ENABLED="false" _set_ccstatusline_command >/dev/null 2>&1
assert_eq "npx -y ccstatusline@latest" \
    "$(jq -r '.statusLine.command' "$HOME/.claude/settings.json")" \
    "command left as npx when ccstatusline disabled"

# ---------------------------------------------------------------------------
suite "End-to-end: merge + repoint settles, re-run makes no .bak, no change"
# ---------------------------------------------------------------------------
_reset
_deploy_ccstatusline_config >/dev/null 2>&1
_merge_claude_settings >/dev/null 2>&1
_set_ccstatusline_command >/dev/null 2>&1
rm -f "$HOME/.claude/settings.json".bak.*    # clear any first-run backup
hb2="$(sha256sum "$HOME/.claude/settings.json" | awk '{print $1}')"
_merge_claude_settings >/dev/null 2>&1
_set_ccstatusline_command >/dev/null 2>&1
ha2="$(sha256sum "$HOME/.claude/settings.json" | awk '{print $1}')"
assert_eq "$hb2" "$ha2" "settled state: no content change on re-run"
assert_eq "0" "$(find "$HOME/.claude" -name 'settings.json.bak.*' 2>/dev/null | wc -l | tr -d ' ')" \
    "settled state: no new .bak on re-run"

# Cleanup
export HOME="$ORIG_HOME"

print_test_summary
