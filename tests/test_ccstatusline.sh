#!/usr/bin/env bash
# test_ccstatusline.sh — Tests for ccstatusline integration in 08-claude-code.sh
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

source "$SCRIPT_DIR/test_framework.sh"
source "$PROJECT_ROOT/lib/common.sh"
source "$PROJECT_ROOT/lib/yaml.sh"
source "$PROJECT_ROOT/lib/dryrun.sh"
source "$PROJECT_ROOT/lib/config.sh"

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

echo -e "${_T_BOLD}Test: 08-claude-code.sh ccstatusline integration${_T_NC}"

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
assert_true "$?" "template is valid JSON"

# ---------------------------------------------------------------------------
suite "Disabled config: nothing happens"
# ---------------------------------------------------------------------------
_reset
CFG_CLAUDE_CODE_CCSTATUSLINE_ENABLED="false" \
    _install_ccstatusline >/dev/null 2>&1
assert_file_not_exists "$HOME/.config/ccstatusline/settings.json" \
    "config not deployed when ccstatusline.enabled=false"
assert_file_not_exists "$HOME/.claude/settings.json" \
    "settings.json not written when ccstatusline.enabled=false"

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
_merge_claude_statusline >/dev/null 2>&1
assert_file_exists "$HOME/.claude/settings.json" "settings.json created"
jq empty "$HOME/.claude/settings.json" 2>/dev/null
assert_true "$?" "created file is valid JSON"
cmd="$(jq -r '.statusLine.command' "$HOME/.claude/settings.json")"
assert_eq "npx -y ccstatusline@latest" "$cmd" \
    "statusLine.command is correct"

# ---------------------------------------------------------------------------
suite "Merge: existing keys are preserved"
# ---------------------------------------------------------------------------
_reset
cat > "$HOME/.claude/settings.json" <<'JSON'
{
  "env": { "FOO": "1" },
  "enabledPlugins": { "plug-a": true },
  "teammateMode": "tmux"
}
JSON
_merge_claude_statusline >/dev/null 2>&1
assert_eq "1"     "$(jq -r '.env.FOO'                   "$HOME/.claude/settings.json")" "env.FOO preserved"
assert_eq "true"  "$(jq -r '.enabledPlugins["plug-a"]'   "$HOME/.claude/settings.json")" "enabledPlugins preserved"
assert_eq "tmux"  "$(jq -r '.teammateMode'              "$HOME/.claude/settings.json")" "teammateMode preserved"
assert_eq "npx -y ccstatusline@latest" \
    "$(jq -r '.statusLine.command' "$HOME/.claude/settings.json")" \
    "statusLine added"

# ---------------------------------------------------------------------------
suite "Merge: idempotent — already correct, no .bak, no content change"
# ---------------------------------------------------------------------------
_reset
cat > "$HOME/.claude/settings.json" <<'JSON'
{
  "statusLine": {
    "type": "command",
    "command": "npx -y ccstatusline@latest",
    "padding": 0,
    "refreshInterval": 10
  }
}
JSON
hash_before="$(sha256sum "$HOME/.claude/settings.json" | awk '{print $1}')"
out="$(_merge_claude_statusline 2>&1)"
hash_after="$(sha256sum "$HOME/.claude/settings.json" | awk '{print $1}')"
assert_eq "$hash_before" "$hash_after" "file content unchanged"
assert_eq "0" "$(find "$HOME/.claude" -name 'settings.json.bak.*' 2>/dev/null | wc -l | tr -d ' ')" \
    "no .bak created for idempotent run"
assert_contains "$out" "already configured" "logs idempotent skip"

# ---------------------------------------------------------------------------
suite "Merge: stale statusLine triggers .bak and updates command"
# ---------------------------------------------------------------------------
_reset
cat > "$HOME/.claude/settings.json" <<'JSON'
{
  "statusLine": { "type": "command", "command": "echo old", "padding": 0 }
}
JSON
_merge_claude_statusline >/dev/null 2>&1
bak="$(find "$HOME/.claude" -maxdepth 1 -name 'settings.json.bak.*' | head -1)"
assert_neq "" "$bak" ".bak created"
assert_contains "$(cat "$bak")" "echo old" "old command preserved in .bak"
assert_eq "npx -y ccstatusline@latest" \
    "$(jq -r '.statusLine.command' "$HOME/.claude/settings.json")" \
    "command updated to ccstatusline"

# ---------------------------------------------------------------------------
suite "Merge: jq missing → log_warn, no mutation"
# ---------------------------------------------------------------------------
_reset
cat > "$HOME/.claude/settings.json" <<'JSON'
{ "teammateMode": "tmux" }
JSON
# Override command_exists to claim jq is missing, then restore so later
# suites do not see jq as missing. shellcheck disable=SC2317 — both
# definitions are reached via indirect invocation from _merge_claude_statusline.
# shellcheck disable=SC2317
command_exists() { [[ "$1" == "jq" ]] && return 1; builtin command -v "$1" &>/dev/null; }
out="$(_merge_claude_statusline 2>&1)"
# shellcheck disable=SC2317
command_exists() { command -v "$1" &>/dev/null; }   # restore lib/common.sh original
assert_contains "$out" "jq" "logs warning mentioning jq"
# File should be untouched
assert_eq "tmux" "$(jq -r '.teammateMode' "$HOME/.claude/settings.json")" \
    "existing settings.json untouched when jq missing"
assert_eq "null" "$(jq -r '.statusLine // "null"' "$HOME/.claude/settings.json")" \
    "no statusLine added when jq missing"

# ---------------------------------------------------------------------------
suite "Merge: malformed JSON → log_error, file unchanged"
# ---------------------------------------------------------------------------
_reset
echo "{ this is not json" > "$HOME/.claude/settings.json"
before="$(cat "$HOME/.claude/settings.json")"
out="$(_merge_claude_statusline 2>&1)"
after="$(cat "$HOME/.claude/settings.json")"
assert_eq "$before" "$after" "malformed file preserved verbatim"
assert_contains "$out" "ERROR" "log_error emitted"

# Cleanup
export HOME="$ORIG_HOME"

print_test_summary
