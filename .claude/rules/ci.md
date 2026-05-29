---
paths:
  - ".github/workflows/*.yml"
---

# CI Workflow Rules

- CI runs directly on `macos-latest` and `ubuntu-latest` runners — no Docker containers
- Matrix must cover both macOS and Ubuntu to match real user environments
- ShellCheck lint step: `shellcheck -x setup.sh bootstrap.sh lib/*.sh modules/*.sh scripts/*.sh`
- Dry-run step: `bash setup.sh --dry-run`
- Do not add container-based jobs — the project explicitly avoids containerised CI
- A `windows-latest` PowerShell lane runs PSScriptAnalyzer, Pester, and
  `setup.ps1 -DryRun` — additive to the macOS/Ubuntu Bash matrix and also not
  container-based. Lint settings live in `PSScriptAnalyzerSettings.psd1`.
