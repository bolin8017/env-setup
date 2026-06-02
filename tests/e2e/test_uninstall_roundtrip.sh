#!/usr/bin/env bash
# test_uninstall_roundtrip.sh — Deploy the shell config layer into a fake HOME,
# then uninstall (default scope, --keep-tools so no real packages are touched)
# and assert the deployed files are gone. Self-contained; safe in CI.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$PROJECT_ROOT/tests/test_framework.sh"

export HOME="${TEST_TMPDIR}/home"
mkdir -p "$HOME"
export ENV_SETUP_DIR="$PROJECT_ROOT"

# --- Deploy the managed shell config exactly as install would ---
mkdir -p "$HOME/.config/zsh/fragments"
cp "$PROJECT_ROOT/configs/zshrc.base" "$HOME/.zshrc"
cp "$PROJECT_ROOT/configs/p10k/.p10k.zsh" "$HOME/.p10k.zsh"
cp "$PROJECT_ROOT/configs/aliases.zsh" "$HOME/.config/zsh/aliases.zsh"
for f in "$PROJECT_ROOT/configs/zshrc/"*.zsh; do
    cp "$f" "$HOME/.config/zsh/fragments/$(basename "$f")"
done
# A user-edited fragment that must survive
echo "# my custom edits" >> "$HOME/.config/zsh/fragments/40-env.zsh"

echo -e "${_T_BOLD}Test: Uninstall round-trip${_T_NC}"
suite "default-scope uninstall removes managed shell config"

# Run uninstall, shell module only, keep-tools (no package ops), auto-yes.
bash "$PROJECT_ROOT/uninstall.sh" --keep-tools --auto-yes --no-restore \
    --modules 06-shell >/dev/null 2>&1

assert_file_not_exists "$HOME/.zshrc" "managed ~/.zshrc removed"
assert_file_not_exists "$HOME/.p10k.zsh" "managed ~/.p10k.zsh removed"
assert_file_not_exists "$HOME/.config/zsh/aliases.zsh" "managed aliases.zsh removed"
assert_file_not_exists "$HOME/.config/zsh/fragments/50-tools.zsh" "clean fragment removed"
assert_file_exists "$HOME/.config/zsh/fragments/40-env.zsh" "user-edited fragment preserved"

print_test_summary
