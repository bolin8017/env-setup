#!/usr/bin/env bash
# test_parser_parity.sh — Cross-engine YAML parser parity.
# The same config.yaml must produce the same values through lib/yaml.sh (Bash)
# and lib/Config.psm1 (PowerShell); a divergence means a feature silently
# behaves differently per platform. Both views are normalized to sorted
# CFG_KEY=value lines and diffed.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

source "$SCRIPT_DIR/test_framework.sh"

export HOME="${TEST_TMPDIR}/home"
mkdir -p "$HOME"

source "$PROJECT_ROOT/lib/common.sh"
source "$PROJECT_ROOT/lib/yaml.sh"

set +e

echo -e "${_T_BOLD}Test: YAML parser parity (bash vs PowerShell)${_T_NC}"

if ! command -v pwsh >/dev/null 2>&1; then
    echo "SKIP: pwsh not available — parity check needs both engines"
    exit 0
fi

# _dump_bash <file> — yaml_parse's eval lines, unquoted, last write wins, sorted.
_dump_bash() {
    yaml_parse "$1" "CFG" | tr -d "\r" | awk '
        match($0, /^([A-Za-z0-9_]+)=\047(.*)\047$/, m) { latest[m[1]] = m[2]; next }
        match($0, /^([A-Za-z0-9_]+)=(.*)$/, m)         { latest[m[1]] = m[2] }
        END { for (k in latest) print k "=" latest[k] }
    ' | sort
}

# _dump_pwsh <file> — raw ConvertFrom-SimpleYaml (module scope; no local-config
# merge, no env overrides) flattened, then renamed into the bash CFG_ scheme
# (upper-case, dots -> underscores) with the COUNT bookkeeping lines bash emits.
_dump_pwsh() {
    # cygpath: Git Bash hands out /c/... paths that pwsh cannot resolve;
    # on Linux CI cygpath is absent and the original path is already fine.
    local ps_root ps_file
    ps_root="$(cygpath -m "$PROJECT_ROOT" 2>/dev/null || echo "$PROJECT_ROOT")"
    ps_file="$(cygpath -m "$1" 2>/dev/null || echo "$1")"
    pwsh -NoProfile -Command "
        Import-Module '$ps_root/lib/Config.psm1'
        & (Get-Module Config) {
            param(\$f)
            \$script:Config = ConvertFrom-SimpleYaml -Lines (Get-Content \$f)
            Get-CfgFlatMap
        } '$ps_file'
    " | tr -d '\r' | awk -F= '
        NF >= 2 {
            key = $1; val = substr($0, index($0, "=") + 1)
            gsub(/[.\-]/, "_", key); key = "CFG_" toupper(key)
            print key "=" val
            # list bookkeeping: an .N suffix implies a COUNT var on the bash
            # side. Track max+1 (the flat map is lexically sorted, so .9 can
            # arrive after .14).
            if (match($1, /^(.*)\.([0-9]+)$/, m)) {
                ck = "CFG_" toupper(m[1]) "_COUNT"; gsub(/[.\-]/, "_", ck)
                if (m[2] + 1 > counts[ck]) counts[ck] = m[2] + 1
            }
        }
        END { for (k in counts) print k "=" counts[k] }
    ' | sort
}

for fixture in "$PROJECT_ROOT/config.yaml.example" "$SCRIPT_DIR/fixtures/parity-cases.yaml"; do
    suite "parity: $(basename "$fixture")"

    _bash_view="$(_dump_bash "$fixture")"
    _pwsh_view="$(_dump_pwsh "$fixture")"

    [[ -n "$_bash_view" ]]
    assert_true $? "bash parser produced output"
    [[ -n "$_pwsh_view" ]]
    assert_true $? "pwsh parser produced output"

    _delta="$(diff <(printf '%s\n' "$_bash_view") <(printf '%s\n' "$_pwsh_view"))"
    if [[ -z "$_delta" ]]; then
        assert_true 0 "engines agree on every key and value"
    else
        echo "$_delta" | head -20
        assert_true 1 "engines agree on every key and value"
    fi
done

print_test_summary
