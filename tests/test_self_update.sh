#!/usr/bin/env bash
# test_self_update.sh — Tests for the self-update state-file writer (06-shell)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

source "$SCRIPT_DIR/test_framework.sh"
source "$PROJECT_ROOT/lib/common.sh"
source "$PROJECT_ROOT/lib/yaml.sh"
source "$PROJECT_ROOT/lib/dryrun.sh"
source "$PROJECT_ROOT/lib/config.sh"
setup_logging
load_config "$PROJECT_ROOT/config.yaml"
export ENV_SETUP_DIR="$PROJECT_ROOT"
# shellcheck source=modules/06-shell.sh
source "$PROJECT_ROOT/modules/06-shell.sh"

echo -e "${_T_BOLD}Test: Self-update state writer${_T_NC}"

suite "_write_update_state writes the state file (not dry-run)"
fake_home="$TEST_TMPDIR/home1"
mkdir -p "$fake_home"
HOME="$fake_home" DRY_RUN="false" _write_update_state
state="$fake_home/.env-setup/update.env"
assert_file_exists "$state" "update.env written"
content="$(cat "$state" 2>/dev/null || echo '')"
assert_contains "$content" "ENVSETUP_REPO_DIR=\"$PROJECT_ROOT\"" "records repo dir"
assert_contains "$content" "ENVSETUP_UPDATE_ENABLED=1" "enabled=1 from config"
assert_contains "$content" "ENVSETUP_UPDATE_FREQ_DAYS=7" "freq_days=7 from config"
assert_file_exists "$fake_home/.env-setup/.update-last-check" "timestamp initialized"

suite "_write_update_state respects dry-run (writes nothing)"
fake_home2="$TEST_TMPDIR/home2"
mkdir -p "$fake_home2"
HOME="$fake_home2" DRY_RUN="true" _write_update_state >/dev/null
assert_file_not_exists "$fake_home2/.env-setup/update.env" "no state file under dry-run"
assert_file_not_exists "$fake_home2/.env-setup/.update-last-check" "no timestamp under dry-run"

print_test_summary
