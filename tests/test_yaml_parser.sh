#!/usr/bin/env bash
# test_yaml_parser.sh — Tests for lib/yaml.sh (cfg_get, cfg_enabled, cfg_list)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

source "$SCRIPT_DIR/test_framework.sh"
source "$PROJECT_ROOT/lib/yaml.sh"

echo -e "${_T_BOLD}Test: YAML Parser${_T_NC}"

# =============================================================================
# Helper: create a YAML fixture and parse it
# =============================================================================
parse_fixture() {
    local yaml_file="$TEST_TMPDIR/fixture.yaml"
    cat > "$yaml_file"
    eval "$(yaml_parse "$yaml_file")"
}

# =============================================================================
suite "Scalar values"
# =============================================================================

parse_fixture <<'YAML'
general:
  auto_yes: true
  dry_run: false
  name: "test-env"
YAML

assert_eq "true"     "$(cfg_get "general.auto_yes")" "boolean true"
assert_eq "false"    "$(cfg_get "general.dry_run")"  "boolean false"
assert_eq "test-env" "$(cfg_get "general.name")"     "quoted string"

# =============================================================================
suite "Nested keys (2+ levels)"
# =============================================================================

parse_fixture <<'YAML'
languages:
  node:
    enabled: true
    version: "lts"
  python:
    enabled: true
    version: "3.12"
  conda:
    enabled: false
YAML

assert_eq "true"  "$(cfg_get "languages.node.enabled")"    "nested boolean (node.enabled)"
assert_eq "lts"   "$(cfg_get "languages.node.version")"    "nested string (node.version)"
assert_eq "3.12"  "$(cfg_get "languages.python.version")"  "nested string (python.version)"
assert_eq "false" "$(cfg_get "languages.conda.enabled")"   "nested boolean false"

# =============================================================================
suite "Lists (cfg_list)"
# =============================================================================

parse_fixture <<'YAML'
shell:
  plugins:
    builtin:
      - git
      - web-search
      - extract
    external:
      - zsh-autosuggestions
      - zsh-syntax-highlighting
YAML

builtin_list="$(cfg_list "shell.plugins.builtin")"
external_list="$(cfg_list "shell.plugins.external")"

assert_contains "$builtin_list"  "git"                   "list contains 'git'"
assert_contains "$builtin_list"  "web-search"            "list contains 'web-search'"
assert_contains "$builtin_list"  "extract"               "list contains 'extract'"
assert_eq "3" "$(echo "$builtin_list" | wc -l | tr -d ' ')" "builtin list has 3 items"

assert_contains "$external_list" "zsh-autosuggestions"    "list contains 'zsh-autosuggestions'"
assert_contains "$external_list" "zsh-syntax-highlighting" "list contains 'zsh-syntax-highlighting'"
assert_eq "2" "$(echo "$external_list" | wc -l | tr -d ' ')" "external list has 2 items"

# =============================================================================
suite "cfg_enabled"
# =============================================================================

parse_fixture <<'YAML'
feature_a: true
feature_b: false
feature_c: True
feature_d: FALSE
YAML

cfg_enabled "feature_a" && rc_a=0 || rc_a=$?
assert_true "$rc_a" "cfg_enabled returns 0 for 'true'"

cfg_enabled "feature_b" && rc_b=0 || rc_b=$?
assert_false "$rc_b" "cfg_enabled returns 1 for 'false'"

cfg_enabled "feature_c" && rc_c=0 || rc_c=$?
assert_true "$rc_c" "cfg_enabled handles 'True' (case-insensitive)"

cfg_enabled "feature_d" && rc_d=0 || rc_d=$?
assert_false "$rc_d" "cfg_enabled handles 'FALSE' (case-insensitive)"

cfg_enabled "nonexistent" && rc_e=0 || rc_e=$?
assert_false "$rc_e" "cfg_enabled returns 1 for missing key"

# =============================================================================
suite "cfg_get for missing keys"
# =============================================================================

parse_fixture <<'YAML'
existing_key: hello
YAML

assert_eq "hello" "$(cfg_get "existing_key")" "existing key returns value"
assert_eq ""      "$(cfg_get "missing_key")"  "missing key returns empty string"
assert_eq ""      "$(cfg_get "a.b.c.d")"      "deeply missing key returns empty string"

# =============================================================================
suite "Comments and whitespace handling"
# =============================================================================

parse_fixture <<'YAML'
# This is a comment
key_a: value_a   # inline comment

  # Indented comment
key_b: value_b

key_c: "quoted with spaces"
YAML

assert_eq "value_a" "$(cfg_get "key_a")" "value before inline comment"
assert_eq "value_b" "$(cfg_get "key_b")" "value after comment-only line"
assert_eq "quoted with spaces" "$(cfg_get "key_c")" "quoted value with spaces"

# =============================================================================
suite "Hyphenated keys"
# =============================================================================

parse_fixture <<'YAML'
cli-tools:
  auto-install: true
YAML

assert_eq "true" "$(cfg_get "cli-tools.auto-install")" "hyphenated keys normalize to underscores"

# =============================================================================
suite "Parse real config.yaml"
# =============================================================================

eval "$(yaml_parse "$PROJECT_ROOT/config.yaml")"

assert_eq "true"  "$(cfg_get "general.auto_yes")"        "real config: general.auto_yes"
assert_eq "true"  "$(cfg_get "general.backup")"           "real config: general.backup"
assert_eq "true"  "$(cfg_get "core.homebrew")"             "real config: core.homebrew"
assert_eq "lts"   "$(cfg_get "languages.node.version")"    "real config: node version"
assert_eq "3.12"  "$(cfg_get "languages.python.version")"  "real config: python version"
assert_eq "false" "$(cfg_get "languages.conda.enabled")"   "real config: conda disabled"
assert_eq "true"  "$(cfg_get "docker.enabled")"            "real config: docker enabled"
assert_eq "true"  "$(cfg_get "cli_tools.fzf")"             "real config: fzf enabled"
assert_eq "true"  "$(cfg_get "shell.oh_my_zsh")"           "real config: oh_my_zsh enabled"
assert_eq "true"  "$(cfg_get "tmux.tpm")"                  "real config: tpm enabled"
assert_eq "true"  "$(cfg_get "npm_globals.claude_cli")"    "real config: claude_cli enabled"

real_plugins="$(cfg_list "shell.plugins.external")"
assert_eq "3" "$(echo "$real_plugins" | wc -l | tr -d ' ')" "real config: 3 external plugins"
assert_contains "$real_plugins" "zsh-autosuggestions"     "real config: autosuggestions plugin"

# =============================================================================
suite "yaml_parse error handling"
# =============================================================================

output="$(yaml_parse "/nonexistent/file.yaml" 2>&1 || true)"
assert_contains "$output" "file not found" "missing file reports error"

# =============================================================================
print_test_summary
