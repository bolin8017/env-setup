#!/usr/bin/env bash
# test_worklog.sh — Worklog module (10-worklog) unit checks
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

source "$SCRIPT_DIR/test_framework.sh"
source "$PROJECT_ROOT/lib/common.sh"
source "$PROJECT_ROOT/lib/yaml.sh"
source "$PROJECT_ROOT/lib/config.sh"
source "$PROJECT_ROOT/lib/dryrun.sh"

setup_logging

# Load the base config in isolation. load_config() also merges a sibling
# config.local.yaml (per-machine overrides such as role: curator), which would
# skew the schema-default assertions below; copying config.yaml into TEST_TMPDIR
# (no sibling override there) keeps this suite hermetic on curator machines.
cp "$PROJECT_ROOT/config.yaml" "$TEST_TMPDIR/config.yaml"
load_config "$TEST_TMPDIR/config.yaml" >/dev/null
export ENV_SETUP_DIR="$PROJECT_ROOT"
DRY_RUN="true"
AUTO_YES="true"

source "$PROJECT_ROOT/modules/10-worklog.sh"

suite "Module entry points"
if declare -f install_worklog >/dev/null; then rc=0; else rc=1; fi
assert_eq "0" "$rc" "10-worklog.sh defines install_worklog()"
if declare -f uninstall_worklog >/dev/null; then rc=0; else rc=1; fi
assert_eq "0" "$rc" "10-worklog.sh defines uninstall_worklog()"

suite "Config schema (all keys the module reads must exist)"
if cfg_enabled "worklog.enabled"; then rc=0; else rc=1; fi
assert_eq "0" "$rc" "worklog.enabled is true by default"
assert_eq "capture" "$(cfg_get worklog.role)" "default role is capture (fail-safe)"
assert_neq "" "$(cfg_get worklog.source)" "worklog.source is set"
assert_neq "" "$(cfg_get worklog.inbox_repo)" "worklog.inbox_repo is set"
assert_neq "" "$(cfg_get worklog.inbox_path)" "worklog.inbox_path is set"
assert_neq "" "$(cfg_get worklog.vault_repo)" "worklog.vault_repo is set"
assert_neq "" "$(cfg_get worklog.vault_path)" "worklog.vault_path is set"

suite "Command assets"
assert_file_exists "$PROJECT_ROOT/configs/worklog/commands/worklog.md" "/worklog command asset exists"
assert_file_exists "$PROJECT_ROOT/configs/worklog/commands/worklog-sync.md" "/worklog-sync command asset exists"

suite "Dry-run install is clean and non-destructive"
out="$(install_worklog 2>&1)"
rc=$?
assert_eq "0" "$rc" "install_worklog returns 0 in dry-run"
assert_contains "$out" "Worklog" "install prints the Worklog header"
assert_contains "$out" "DRY-RUN" "dry-run mode logs [DRY-RUN] (no real writes)"

print_test_summary
