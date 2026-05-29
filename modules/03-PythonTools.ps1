#!/usr/bin/env pwsh
# 03-PythonTools.ps1 — uv (scoop) + poetry/jupyter (pipx). Gated on Python being
# enabled, mirroring 03-python-tools.sh.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module "$PSScriptRoot/../lib/Common.psm1"
Import-Module "$PSScriptRoot/../lib/Config.psm1"
Import-Module "$PSScriptRoot/../lib/Package.psm1"

function Install-PythonTools {
    Write-Header 'Python tools'
    if (-not (Test-CfgEnabled 'languages.python.enabled')) {
        Write-Info 'Python disabled — skipping Python tools'
        return
    }

    if (Test-CfgEnabled 'python_tools.uv') { Install-Pkg -Name 'uv' }

    # poetry and jupyter go through pipx (isolated venvs); ensure pipx first.
    $needPipx = (Test-CfgEnabled 'python_tools.poetry') -or (Test-CfgEnabled 'python_tools.jupyter')
    if ($needPipx) { Install-Pkg -Name 'pipx' }

    if (Test-CfgEnabled 'python_tools.poetry') {
        if (Test-DryRun) { Write-Info '[DRY-RUN] Would run: pipx install poetry' } else { pipx install poetry }
    }
    if (Test-CfgEnabled 'python_tools.jupyter') {
        if (Test-DryRun) { Write-Info '[DRY-RUN] Would run: pipx install jupyterlab' } else { pipx install jupyterlab }
    }
}
