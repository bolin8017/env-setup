#!/usr/bin/env bash
# test_fragments.sh — Verify zsh fragment system completeness and validity
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

source "$SCRIPT_DIR/test_framework.sh"

echo -e "${_T_BOLD}Test: Fragment System${_T_NC}"

FRAG_DIR="$PROJECT_ROOT/configs/zshrc"

# =============================================================================
suite "Required fragment files exist"
# =============================================================================

required_fragments=(
    "00-p10k-instant-prompt.zsh"
    "10-omz.zsh"
    "20-history.zsh"
    "30-completion.zsh"
    "40-env.zsh"
    "50-tools.zsh"
    "60-aliases.zsh"
    "99-p10k-config.zsh"
)

for frag in "${required_fragments[@]}"; do
    assert_file_exists "$FRAG_DIR/$frag" "fragment: $frag"
done

# =============================================================================
suite "zshrc.base exists and sources fragments"
# =============================================================================

assert_file_exists "$PROJECT_ROOT/configs/zshrc.base" "zshrc.base exists"

base_content="$(cat "$PROJECT_ROOT/configs/zshrc.base")"
assert_contains "$base_content" "fragments" "zshrc.base references fragments directory"
assert_contains "$base_content" "custom"    "zshrc.base references custom directory"

# =============================================================================
suite "Fragment numbering is correct (sorted order = dependency order)"
# =============================================================================

prev_num=-1
for frag in "$FRAG_DIR"/*.zsh; do
    name="$(basename "$frag")"
    num="$(echo "$name" | grep -oE '^[0-9]+' | sed 's/^0*//')"
    [[ -z "$num" ]] && num=0  # Handle 00-*

    (( _TEST_TOTAL += 1 ))
    if [[ "$num" -gt "$prev_num" ]]; then
        echo -e "  ${_T_GREEN}PASS${_T_NC}  ${name} (${num}) > previous (${prev_num})"
        (( _TEST_PASS += 1 ))
    else
        echo -e "  ${_T_RED}FAIL${_T_NC}  ${name} (${num}) not after previous (${prev_num})"
        (( _TEST_FAIL += 1 ))
    fi
    prev_num=$num
done

# =============================================================================
suite "Fragment content — critical sections present"
# =============================================================================

# 00: P10k instant prompt
content_00="$(cat "$FRAG_DIR/00-p10k-instant-prompt.zsh")"
assert_contains "$content_00" "p10k-instant-prompt" "00: contains p10k instant prompt"

# 10: Oh My Zsh setup
content_10="$(cat "$FRAG_DIR/10-omz.zsh")"
assert_contains "$content_10" 'ZSH="$HOME/.oh-my-zsh"'  "10: sets ZSH path"
assert_contains "$content_10" "plugins="                  "10: defines plugins list"
assert_contains "$content_10" "oh-my-zsh.sh"              "10: sources oh-my-zsh"
assert_contains "$content_10" "powerlevel10k"              "10: sets p10k theme"

# 20: History
content_20="$(cat "$FRAG_DIR/20-history.zsh")"
assert_contains "$content_20" "HISTSIZE"       "20: sets HISTSIZE"
assert_contains "$content_20" "SAVEHIST"       "20: sets SAVEHIST"
assert_contains "$content_20" "SHARE_HISTORY"  "20: enables shared history"

# 30: Completion
content_30="$(cat "$FRAG_DIR/30-completion.zsh")"
assert_contains "$content_30" "completion" "30: has completion config"
assert_contains "$content_30" "zsh-completions" "30: references zsh-completions"

# 40: Environment
content_40="$(cat "$FRAG_DIR/40-env.zsh")"
assert_contains "$content_40" "EDITOR" "40: sets EDITOR"
assert_contains "$content_40" "LANG"   "40: sets LANG"
assert_contains "$content_40" "PATH"   "40: modifies PATH"

# 50: Tool integrations
content_50="$(cat "$FRAG_DIR/50-tools.zsh")"
assert_contains "$content_50" "fzf"    "50: has fzf integration"
assert_contains "$content_50" "zoxide" "50: has zoxide integration"
assert_contains "$content_50" "bat"    "50: has bat integration"
# All tool integrations guarded with command -v
assert_contains "$content_50" "command -v" "50: tools are guarded with command -v"

# 60: Aliases
content_60="$(cat "$FRAG_DIR/60-aliases.zsh")"
assert_contains "$content_60" "aliases.zsh" "60: sources aliases file"

# 99: P10k config
content_99="$(cat "$FRAG_DIR/99-p10k-config.zsh")"
assert_contains "$content_99" ".p10k.zsh" "99: sources p10k config"

# =============================================================================
suite "Aliases file completeness"
# =============================================================================

aliases_content="$(cat "$PROJECT_ROOT/configs/aliases.zsh")"
assert_contains "$aliases_content" "ll="     "aliases: defines ll"
assert_contains "$aliases_content" "gs="     "aliases: defines gs (git status)"
assert_contains "$aliases_content" "cat="    "aliases: defines cat (bat alias)"
assert_contains "$aliases_content" "eza"     "aliases: references eza"
assert_contains "$aliases_content" "batcat"  "aliases: handles batcat (Ubuntu)"
assert_contains "$aliases_content" "fdfind"  "aliases: handles fdfind (Ubuntu)"
assert_contains "$aliases_content" "cp -i"   "aliases: safety alias for cp"
assert_contains "$aliases_content" "rm -i"   "aliases: safety alias for rm"

# =============================================================================
suite "Tmux config files"
# =============================================================================

assert_file_exists "$PROJECT_ROOT/configs/tmux/tmux.conf"       "tmux.conf exists"
assert_file_exists "$PROJECT_ROOT/configs/tmux/tmux.macos.conf" "tmux.macos.conf exists"
assert_file_exists "$PROJECT_ROOT/configs/tmux/dev-layout.conf" "dev-layout.conf exists"

tmux_content="$(cat "$PROJECT_ROOT/configs/tmux/tmux.conf")"
assert_contains "$tmux_content" "prefix"    "tmux.conf: sets prefix key"
assert_contains "$tmux_content" "tpm"       "tmux.conf: references TPM"
assert_contains "$tmux_content" "resurrect" "tmux.conf: includes resurrect plugin"

# =============================================================================
suite "P10k config file"
# =============================================================================

assert_file_exists "$PROJECT_ROOT/configs/p10k/.p10k.zsh" "p10k config exists"

# =============================================================================
print_test_summary
