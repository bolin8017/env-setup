#!/usr/bin/env bash
# test_claude_assets.sh — Consistency checks for configs/claude/ assets.
# Catches broken JSON, whitelist typos, unregistered plugin marketplaces, and
# missing frontmatter BEFORE they reach a fresh machine's install.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

source "$SCRIPT_DIR/test_framework.sh"

export HOME="${TEST_TMPDIR}/home"
mkdir -p "$HOME"

source "$PROJECT_ROOT/lib/common.sh"
source "$PROJECT_ROOT/lib/yaml.sh"
source "$PROJECT_ROOT/lib/dryrun.sh"
source "$PROJECT_ROOT/lib/config.sh"
setup_logging
load_config "$PROJECT_ROOT/config.yaml"

set +e

echo -e "${_T_BOLD}Test: Claude config assets${_T_NC}"

CLAUDE_DIR="$PROJECT_ROOT/configs/claude"
SETTINGS="$CLAUDE_DIR/settings.json"

if ! command -v jq >/dev/null 2>&1; then
    echo "SKIP: jq not installed — claude asset checks need jq"
    exit 0
fi

# =============================================================================
suite "JSON assets parse"
# =============================================================================

jq empty "$SETTINGS" 2>/dev/null
assert_true $? "settings.json is valid JSON"
jq empty "$CLAUDE_DIR/mcp-servers.json" 2>/dev/null
assert_true $? "mcp-servers.json is valid JSON"

# =============================================================================
suite "settings_merge_keys whitelist matches settings.json"
# =============================================================================

# A typo'd whitelist key would silently merge nothing for that key.
while IFS= read -r key; do
    [[ -z "$key" ]] && continue
    [[ "$(jq --arg k "$key" 'has($k)' "$SETTINGS")" == "true" ]]
    assert_true $? "whitelist key '$key' exists in settings.json"
done < <(cfg_list "claude_code.settings_merge_keys")

# =============================================================================
suite "enabledPlugins marketplaces are registered"
# =============================================================================

# A plugin whose @marketplace suffix isn't in claude_code.marketplaces cannot
# resolve on a fresh machine.
# tr -d '\r': tolerate CRLF checkouts (Git Bash on Windows with autocrlf).
_registered="$(cfg_list "claude_code.marketplaces" | tr -d '\r' | while IFS= read -r m; do basename "$m"; done)"
while IFS= read -r plugin; do
    plugin="${plugin%$'\r'}"
    [[ -z "$plugin" ]] && continue
    _mp="${plugin##*@}"
    grep -qxF "$_mp" <<< "$_registered"
    assert_true $? "plugin '$plugin' marketplace '$_mp' is registered"
done < <(jq -r '.enabledPlugins | to_entries[] | select(.value == true) | .key' "$SETTINGS")

# =============================================================================
suite "markdown assets carry frontmatter"
# =============================================================================

_check_frontmatter() {
    local f="$1" label="$2"
    [[ "$(head -n 1 "$f" | tr -d '\r')" == "---" ]]
    assert_true $? "$label starts with YAML frontmatter"
    awk '/^---$/{n++} n==1 && /^description:/{found=1} n>=2{exit} END{exit !found}' "$f"
    assert_true $? "$label frontmatter has a description"
}

shopt -s nullglob
for f in "$CLAUDE_DIR/commands"/*.md; do
    _check_frontmatter "$f" "command $(basename "$f")"
done
for f in "$CLAUDE_DIR/skills"/*/SKILL.md; do
    _check_frontmatter "$f" "skill $(basename "$(dirname "$f")")"
done
shopt -u nullglob

# =============================================================================
suite "skills tree shape"
# =============================================================================

# Every skill directory must contain a SKILL.md (the loader's entry point).
shopt -s nullglob
for d in "$CLAUDE_DIR/skills"/*/; do
    [[ -f "${d}SKILL.md" ]]
    assert_true $? "skill dir $(basename "$d") contains SKILL.md"
done
shopt -u nullglob

print_test_summary
