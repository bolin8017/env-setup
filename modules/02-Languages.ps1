#!/usr/bin/env pwsh
# 02-Languages.ps1 — nvm-windows + pyenv-win. PATH/shim wiring into $PROFILE is
# added with the shell profile in Stage 3.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module "$PSScriptRoot/../lib/Common.psm1"
Import-Module "$PSScriptRoot/../lib/Config.psm1"
Import-Module "$PSScriptRoot/../lib/Package.psm1"

function Install-Languages {
    Write-Header 'Languages'

    if (Test-CfgEnabled 'languages.node.enabled') {
        Install-Pkg -Name 'nvm'        # coreybutler/nvm-windows
        $ver = Get-CfgValue 'languages.node.version'
        if (-not $ver) { $ver = 'lts' }
        if (Test-DryRun) { Write-Info "[DRY-RUN] Would run: nvm install $ver; nvm use $ver" }
        else { nvm install $ver; nvm use $ver }
    }

    if (Test-CfgEnabled 'languages.python.enabled') {
        Install-Pkg -Name 'pyenv'      # pyenv-win
        $pyver = Get-CfgValue 'languages.python.version'
        if ($pyver) {
            if (Test-DryRun) { Write-Info "[DRY-RUN] Would run: pyenv install $pyver; pyenv global $pyver" }
            else { pyenv install $pyver; pyenv global $pyver }
        }
    }

    Write-Info 'nvm/pyenv PATH wiring is added with the PowerShell profile in Stage 3.'
}
