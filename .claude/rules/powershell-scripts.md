---
paths:
  - "setup.ps1"
  - "bootstrap.ps1"
  - "lib/*.psm1"
  - "modules/*.ps1"
  - "tests/*.Tests.ps1"
---

# PowerShell Script Conventions (Windows engine)

- Shebang `#!/usr/bin/env pwsh`; `Set-StrictMode -Version Latest` and
  `$ErrorActionPreference = 'Stop'` at the top of every script/module.
- Use approved verbs (`Get-`, `Set-`, `Install-`, `Test-`, `Invoke-`, ...).
- Library files are `lib/*.psm1` and `Export-ModuleMember` their public
  functions; private helpers are not exported.
- Cross-module flags travel via `ENVSETUP_DRY_RUN` / `ENVSETUP_AUTO_YES` /
  `ENVSETUP_KEEP_EXISTING` (read through Common.psm1 helpers).
- Gate features on config with `Test-CfgEnabled 'section.key'`.
- Route mutating actions through `Invoke-OrDryRun` / `Copy-OrDryRun` /
  `New-DirOrDryRun` / `Deploy-Config`.
- All scripts must pass `Invoke-ScriptAnalyzer` with
  `PSScriptAnalyzerSettings.psd1` at Error+Warning severity.
- Module entry point function is `Install-<ModuleName>` (e.g. `Install-Shell`).
- Tests use Pester 5: every `BeforeEach`/`AfterEach` must live inside a
  `Describe`/`Context` (Pester rejects setup blocks at the file root).
