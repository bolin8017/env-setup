#!/usr/bin/env bash
# test_config_consistency.sh — Verify config.yaml, config.yaml.example, and CLAUDE.md stay in sync
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

source "$SCRIPT_DIR/test_framework.sh"

echo -e "${_T_BOLD}Test: Config & Documentation Consistency${_T_NC}"

# =============================================================================
suite "config.yaml vs config.yaml.example"
# =============================================================================

diff_output="$(diff "$PROJECT_ROOT/config.yaml" "$PROJECT_ROOT/config.yaml.example" 2>&1 || true)"
assert_eq "" "$diff_output" "config.yaml and config.yaml.example are identical"

# =============================================================================
suite "All config keys parsed by modules exist in config.yaml"
# =============================================================================

# Extract cfg_get/cfg_enabled/cfg_list calls from all source files
declare -A config_keys
while IFS= read -r key; do
    [[ -z "$key" ]] && continue
    config_keys["$key"]=1
done < <(
    grep -rhoE 'cfg_(get|enabled|list) "[^"]+"' "$PROJECT_ROOT/setup.sh" "$PROJECT_ROOT/modules/"*.sh 2>/dev/null \
    | sed 's/cfg_[a-z]* "\(.*\)"/\1/' \
    | grep -v '[${}]' \
    | sort -u
)

# Parse config.yaml and check each key exists
source "$PROJECT_ROOT/lib/common.sh"
source "$PROJECT_ROOT/lib/yaml.sh"
setup_logging
eval "$(yaml_parse "$PROJECT_ROOT/config.yaml")"

for key in "${!config_keys[@]}"; do
    # For list keys, check the _COUNT variable
    varname="CFG_$(echo "$key" | tr '.' '_' | tr '-' '_' | tr '[:lower:]' '[:upper:]')"
    count_var="${varname}_COUNT"
    if [[ -n "${!varname:-}" ]] || [[ -n "${!count_var:-}" ]]; then
        (( _TEST_TOTAL += 1 ))
        echo -e "  ${_T_GREEN}PASS${_T_NC}  config key exists: $key"
        (( _TEST_PASS += 1 ))
    else
        (( _TEST_TOTAL += 1 ))
        echo -e "  ${_T_RED}FAIL${_T_NC}  config key missing: $key (used in code but not in config.yaml)"
        (( _TEST_FAIL += 1 ))
    fi
done

# =============================================================================
suite "CLAUDE.md references correct module files"
# =============================================================================

if [[ -f "$PROJECT_ROOT/CLAUDE.md" ]]; then
    # Extract module filenames from CLAUDE.md
    while IFS= read -r module_ref; do
        [[ -z "$module_ref" ]] && continue
        if [[ -f "$PROJECT_ROOT/modules/$module_ref" ]]; then
            (( _TEST_TOTAL += 1 ))
            echo -e "  ${_T_GREEN}PASS${_T_NC}  CLAUDE.md module exists: $module_ref"
            (( _TEST_PASS += 1 ))
        else
            (( _TEST_TOTAL += 1 ))
            echo -e "  ${_T_RED}FAIL${_T_NC}  CLAUDE.md references missing module: $module_ref"
            (( _TEST_FAIL += 1 ))
        fi
    done < <(grep -oE '[0-9]+-[a-z_-]+\.sh' "$PROJECT_ROOT/CLAUDE.md" | sort -u)

    # Extract lib filenames from CLAUDE.md
    while IFS= read -r lib_ref; do
        [[ -z "$lib_ref" ]] && continue
        if [[ -f "$PROJECT_ROOT/lib/$lib_ref" ]]; then
            (( _TEST_TOTAL += 1 ))
            echo -e "  ${_T_GREEN}PASS${_T_NC}  CLAUDE.md lib exists: $lib_ref"
            (( _TEST_PASS += 1 ))
        else
            (( _TEST_TOTAL += 1 ))
            echo -e "  ${_T_RED}FAIL${_T_NC}  CLAUDE.md references missing lib: $lib_ref"
            (( _TEST_FAIL += 1 ))
        fi
    done < <(grep -oE '│[[:space:]]*├── [a-z_]+\.sh' "$PROJECT_ROOT/CLAUDE.md" \
             | sed 's/.*├── //' | sort -u)
else
    (( _TEST_TOTAL += 1 ))
    echo -e "  ${_T_RED}FAIL${_T_NC}  CLAUDE.md not found"
    (( _TEST_FAIL += 1 ))
fi

# =============================================================================
suite "CLAUDE.md references correct lib files"
# =============================================================================

# Extract all *.sh filenames mentioned in CLAUDE.md directory tree
while IFS= read -r mentioned_file; do
    [[ -z "$mentioned_file" ]] && continue
    # Check if it exists in any project directory
    if [[ -f "$PROJECT_ROOT/lib/$mentioned_file" ]] || \
       [[ -f "$PROJECT_ROOT/modules/$mentioned_file" ]] || \
       [[ -f "$PROJECT_ROOT/$mentioned_file" ]] || \
       [[ -f "$PROJECT_ROOT/scripts/$mentioned_file" ]] || \
       [[ -f "$PROJECT_ROOT/tests/$mentioned_file" ]]; then
        (( _TEST_TOTAL += 1 ))
        echo -e "  ${_T_GREEN}PASS${_T_NC}  documented file exists: $mentioned_file"
        (( _TEST_PASS += 1 ))
    else
        (( _TEST_TOTAL += 1 ))
        echo -e "  ${_T_RED}FAIL${_T_NC}  documented file missing: $mentioned_file"
        (( _TEST_FAIL += 1 ))
    fi
done < <(grep -oE '[0-9a-z_-]+\.sh' "$PROJECT_ROOT/CLAUDE.md" \
         | grep -v '^#' | sort -u)

# =============================================================================
print_test_summary
