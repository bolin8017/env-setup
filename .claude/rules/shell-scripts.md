---
paths:
  - "modules/*.sh"
  - "lib/*.sh"
  - "scripts/*.sh"
  - "setup.sh"
  - "bootstrap.sh"
---

# Shell Script Conventions

## Shebang and Guards

- Always use `#!/usr/bin/env bash`
- Library files (`lib/`) must include a double-source guard:
  ```bash
  [[ -n "${_ENV_SETUP_<NAME>_LOADED:-}" ]] && return 0
  _ENV_SETUP_<NAME>_LOADED=1
  ```
- Only set `set -euo pipefail` behind a standalone guard:
  ```bash
  if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
      set -euo pipefail
  fi
  ```

## Naming

- Private/internal functions: `_prefixed` (e.g., `_install_homebrew`)
- Public entry points: no underscore (e.g., `install_core`)
- Module entry point function: `install_<module_name>`

## Structure

- Use section separators for major blocks:
  ```bash
  # =============================================================================
  # Section Name
  # =============================================================================
  ```
- Each install function should be idempotent — check with `command_exists` before installing
- Use `cfg_enabled "section.key"` to gate features on config.yaml values
- Use `dry_run_cmd` for any command that modifies the system

## Logging

- `log_info` for progress messages
- `log_success` for completed steps
- `log_warn` for non-fatal issues
- `log_error` for failures (writes to stderr)
- `print_header` for top-level section banners

## Platform Handling

- Use `is_macos`, `is_linux`, `is_wsl` helpers — never raw `uname` checks
- Use `pkg_install` abstraction instead of raw `brew install` or `apt-get install`

## ShellCheck

- All scripts must pass `shellcheck -x`
- Suppression directives from `.shellcheckrc`: SC1091, SC2181
- Add inline `# shellcheck disable=SCXXXX` only with a comment explaining why
