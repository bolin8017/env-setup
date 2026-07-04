#!/usr/bin/env pwsh
# 02-Languages.ps1 - nvm-windows + uv-managed Python. PATH wiring comes from the
# scoop manifests: nvm registers a shim; uv's manifest persists the python/tools
# shim dirs (UV_PYTHON_BIN_DIR et al.) and adds them to the user PATH.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module "$PSScriptRoot/../lib/Common.psm1"
Import-Module "$PSScriptRoot/../lib/Config.psm1"
Import-Module "$PSScriptRoot/../lib/Package.psm1"
Import-Module "$PSScriptRoot/../lib/Uninstall.psm1"

function Install-Languages {
    Write-Header 'Languages'

    if (Test-CfgEnabled 'languages.node.enabled') {
        Install-Pkg -Name 'nvm'        # coreybutler/nvm-windows
        $ver = Get-CfgValue 'languages.node.version'
        if (-not $ver) { $ver = 'lts' }
        if (Test-DryRun) { Write-Info "[DRY-RUN] Would run: nvm install $ver; nvm use $ver" }
        else {
            nvm install $ver
            if ($LASTEXITCODE -ne 0) { Write-Warn "nvm install $ver exited $LASTEXITCODE" }
            # nvm-windows creates a symlink; without Developer Mode or an
            # elevated shell this quietly fails and node stays unusable.
            nvm use $ver
            if ($LASTEXITCODE -ne 0) { Write-Warn "nvm use $ver exited $LASTEXITCODE (needs Developer Mode or one elevated 'nvm use')" }
        }
    }

    if (Test-CfgEnabled 'languages.python.enabled') {
        Install-Pkg -Name 'uv'
        $pyver = Get-CfgValue 'languages.python.version'
        if ($pyver) {
            if (Test-DryRun) { Write-Info "[DRY-RUN] Would run: uv python install $pyver --default" }
            else {
                # uv resolves "3.12" to its newest patch itself and installs a
                # prebuilt standalone CPython - no version-list cache, no MSI
                # admin-install, no compiler. --default (uv preview feature)
                # additionally creates bare python/python3 shims, the moral
                # equivalent of `pyenv global`. Managed versions also register
                # in the Windows registry (PEP 514), so `py` sees them.
                uv python install $pyver --default
                if ($LASTEXITCODE -ne 0) { Write-Warn "uv python install $pyver exited $LASTEXITCODE" }
            }
        }
    }
}

function Uninstall-Languages {
    Write-Header 'Uninstall: Languages'
    if (-not (Test-KeepTools)) {
        # uv-managed CPython + shims. Teardown runs modules in reverse
        # (09->01), so Uninstall-PythonTools (03) has already removed the uv
        # app by the time this runs - ask uv only if it survived, otherwise
        # fall back to the scoop persist layout the manifest pins.
        $pyDirs = @()
        if (Test-Command 'uv') {
            $pyDirs = @((& uv python dir 2>$null), (& uv python dir --bin 2>$null))
        } else {
            $persist = Join-Path $HOME 'scoop\persist\uv\python'
            if (Test-Path $persist) { $pyDirs = @($persist) }
        }
        foreach ($d in $pyDirs) {
            if ($d) { Remove-ManagedDir -Dir $d -Label 'uv-managed Python' }
        }
        # Legacy: machines provisioned before the uv migration used pyenv-win.
        Remove-Pkg -Name 'pyenv'
        Remove-ManagedDir -Dir (Join-Path $HOME '.pyenv') -Label 'pyenv-win data'
        Remove-Pkg -Name 'nvm'
    }
}
