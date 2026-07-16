#!/usr/bin/env bash
# test_episodic_memory_patch.sh — Unit tests for _patch_episodic_memory_deps in
# modules/08-claude-code.sh.
#
# The episodic-memory marketplace plugin ships a broken lockfile: npm nests
# onnxruntime-common under onnxruntime-node/ (and onnxruntime-web/) instead of
# hoisting it, so @huggingface/transformers' bare `import "onnxruntime-common"`
# fails to resolve and the plugin's SessionStart hook errors out. The patch
# hoists the nested copy to top-level node_modules via a symlink.
#
# These tests verify the symlink is created only when the nested copy exists and
# the top-level is missing/broken, is idempotent, never clobbers a real
# top-level dir, and honours dry-run.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

source "$SCRIPT_DIR/test_framework.sh"

# Sandbox HOME before lib/common.sh binds LOG_DIR.
export HOME="${TEST_TMPDIR}/home"
mkdir -p "$HOME"

source "$PROJECT_ROOT/lib/common.sh"
source "$PROJECT_ROOT/lib/yaml.sh"
source "$PROJECT_ROOT/lib/dryrun.sh"
source "$PROJECT_ROOT/lib/config.sh"
setup_logging
load_config "$PROJECT_ROOT/config.yaml"
export ENV_SETUP_DIR="$PROJECT_ROOT"

# shellcheck source=/dev/null
source "$PROJECT_ROOT/modules/08-claude-code.sh"

set +e

echo -e "${_T_BOLD}Test: episodic-memory onnxruntime-common patch${_T_NC}"

EM_BASE="$HOME/.claude/plugins/cache/superpowers-marketplace/episodic-memory"

# _make_plugin <version> [with_nested=1] — build a fake plugin cache tree.
# When with_nested=1, plant the nested onnxruntime-common copy npm buries under
# onnxruntime-node/ (the thing the patch hoists).
_make_plugin() {
    local ver="$1" nested="${2:-1}"
    local nm="$EM_BASE/$ver/node_modules"
    mkdir -p "$nm"
    if [[ "$nested" == "1" ]]; then
        mkdir -p "$nm/onnxruntime-node/node_modules/onnxruntime-common"
        : > "$nm/onnxruntime-node/node_modules/onnxruntime-common/package.json"
    fi
}
_reset() { rm -rf "$EM_BASE"; }

# =============================================================================
suite "creates hoist symlink when nested exists and top-level missing"
# =============================================================================
_reset; _make_plugin "1.4.2"
DRY_RUN=false _patch_episodic_memory_deps >/dev/null 2>&1
dest="$EM_BASE/1.4.2/node_modules/onnxruntime-common"
[[ -L "$dest" ]]; assert_true $? "top-level onnxruntime-common is a symlink"
[[ -d "$dest" ]]; assert_true $? "symlink resolves to a directory"
[[ -f "$dest/package.json" ]]; assert_true $? "resolves to the nested copy"

# =============================================================================
suite "idempotent — second run keeps the symlink"
# =============================================================================
DRY_RUN=false _patch_episodic_memory_deps >/dev/null 2>&1
[[ -L "$dest" ]]; assert_true $? "symlink still present after a second run"

# =============================================================================
suite "does not clobber a real top-level onnxruntime-common dir"
# =============================================================================
_reset; _make_plugin "1.4.2"
realdest="$EM_BASE/1.4.2/node_modules/onnxruntime-common"
mkdir -p "$realdest"; : > "$realdest/REAL_MARKER"
DRY_RUN=false _patch_episodic_memory_deps >/dev/null 2>&1
[[ ! -L "$realdest" ]]; assert_true $? "real dir left as a dir, not replaced by a symlink"
[[ -f "$realdest/REAL_MARKER" ]]; assert_true $? "real dir contents preserved"

# =============================================================================
suite "leaves an existing top-level link untouched"
# =============================================================================
_reset; _make_plugin "1.4.2"
dest="$EM_BASE/1.4.2/node_modules/onnxruntime-common"
ln -s "/some/other/target" "$dest"
DRY_RUN=false _patch_episodic_memory_deps >/dev/null 2>&1
[[ "$(readlink "$dest")" == "/some/other/target" ]]
assert_true $? "existing link left pointing at its original target"

# =============================================================================
suite "no-op when nested copy absent"
# =============================================================================
_reset; _make_plugin "1.4.2" 0
DRY_RUN=false _patch_episodic_memory_deps >/dev/null 2>&1
dest="$EM_BASE/1.4.2/node_modules/onnxruntime-common"
[[ ! -e "$dest" ]]; assert_true $? "no link created when there is nothing to hoist"

# =============================================================================
suite "no-op and success when plugin not installed"
# =============================================================================
_reset
DRY_RUN=false _patch_episodic_memory_deps >/dev/null 2>&1; rc=$?
assert_true "$rc" "returns 0 when the plugin dir is absent"

# =============================================================================
suite "dry-run does not create the symlink"
# =============================================================================
_reset; _make_plugin "1.4.2"
out="$(DRY_RUN=true _patch_episodic_memory_deps 2>&1)"
dest="$EM_BASE/1.4.2/node_modules/onnxruntime-common"
[[ ! -e "$dest" ]]; assert_true $? "dry-run creates no symlink"
assert_contains "$out" "DRY-RUN" "dry-run announces the intended link"

# =============================================================================
suite "patches every installed version dir"
# =============================================================================
_reset; _make_plugin "1.4.2"; _make_plugin "1.5.0"
DRY_RUN=false _patch_episodic_memory_deps >/dev/null 2>&1
[[ -L "$EM_BASE/1.4.2/node_modules/onnxruntime-common" ]]; assert_true $? "1.4.2 linked"
[[ -L "$EM_BASE/1.5.0/node_modules/onnxruntime-common" ]]; assert_true $? "1.5.0 linked"

print_test_summary
