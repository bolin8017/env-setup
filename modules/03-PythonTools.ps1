#!/usr/bin/env pwsh
# 03-PythonTools.ps1 - poetry/jupyter as isolated uv tools. Gated on Python
# being enabled, mirroring 03-python-tools.sh. uv itself is installed by
# 02-Languages (it is the Python manager); its scoop manifest already exposes
# the tools shim dir on the user PATH.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module "$PSScriptRoot/../lib/Common.psm1"
Import-Module "$PSScriptRoot/../lib/Config.psm1"
Import-Module "$PSScriptRoot/../lib/Package.psm1"

function Install-PythonTools {
    Write-Header 'Python tools'
    if (-not (Test-CfgEnabled 'languages.python.enabled')) {
        Write-Info 'Python disabled - skipping Python tools'
        return
    }

    if (Test-CfgEnabled 'python_tools.poetry') {
        if (Test-Command 'poetry') { Write-Success 'Poetry already installed' }
        elseif (Test-DryRun) { Write-Info '[DRY-RUN] Would run: uv tool install poetry' }
        else { uv tool install poetry }
    }
    if (Test-CfgEnabled 'python_tools.jupyter') {
        if (Test-Command 'jupyter-lab') { Write-Success 'JupyterLab already installed' }
        elseif (Test-DryRun) { Write-Info '[DRY-RUN] Would run: uv tool install jupyterlab' }
        else { uv tool install jupyterlab }
    }
}

function Uninstall-PythonTools {
    Write-Header 'Uninstall: Python tools'
    if (-not (Test-KeepTools)) {
        # uv-tool venvs (post-migration installs); no-ops when absent. Must
        # run while uv is still installed.
        if (Test-Command 'uv') {
            if (Test-DryRun) {
                Write-Info '[DRY-RUN] Would run: uv tool uninstall poetry; uv tool uninstall jupyterlab'
            } else {
                Invoke-Native uv tool uninstall poetry | Out-Null
                Invoke-Native uv tool uninstall jupyterlab | Out-Null
            }
        }
        # Legacy pipx-managed tools (pre-uv-migration installs)
        if (Test-Command 'pipx') {
            if (Test-DryRun) {
                Write-Info '[DRY-RUN] Would run: pipx uninstall poetry; pipx uninstall jupyterlab'
            } else {
                Invoke-Native pipx uninstall poetry | Out-Null
                Invoke-Native pipx uninstall jupyterlab | Out-Null
            }
        }
        Remove-Pkg -Name 'uv'
        Remove-Pkg -Name 'pipx'   # legacy (pre-uv-migration installs)
    }
}
