#!/usr/bin/env pwsh
# 02-Languages.ps1 — nvm-windows + pyenv-win. PATH/shim wiring into $PROFILE is
# added with the shell profile in Stage 3.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module "$PSScriptRoot/../lib/Common.psm1"
Import-Module "$PSScriptRoot/../lib/Config.psm1"
Import-Module "$PSScriptRoot/../lib/Package.psm1"

function Resolve-PyenvVersion {
    # pyenv-win needs an exact patch version. Given a major.minor request like
    # "3.12" plus the lines of `pyenv install --list`, return the newest matching
    # "3.12.<patch>" (stable only). Returns $Requested unchanged if it already
    # carries a patch component or nothing matches. Pure, so it is unit-testable.
    param(
        [Parameter(Mandatory)][string]$Requested,
        [string[]]$Available = @()
    )
    if ($Requested -notmatch '^\d+\.\d+$') { return $Requested }
    $rx = '^' + [regex]::Escape($Requested) + '\.\d+$'
    $match = $Available |
        ForEach-Object { $_.Trim() } |
        Where-Object { $_ -match $rx } |
        Sort-Object { [version]$_ } |
        Select-Object -Last 1
    if ($match) { return $match }
    return $Requested
}

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
            else {
                # pyenv-win, unlike *nix pyenv, won't resolve "3.12" to its newest
                # patch ("definition not found: 3.12"). Map major.minor to an exact
                # patch from the available list before installing.
                if ($pyver -match '^\d+\.\d+$') {
                    # pyenv-win ships a cached version DB that can predate recent
                    # patch releases. Try to refresh it, but its updater is an
                    # htmlfile-based VBScript that throws on some machines — catch
                    # it so a broken 'pyenv update' can't abort the whole module.
                    try {
                        Write-Info 'Refreshing pyenv-win version list (pyenv update)...'
                        pyenv update *> $null
                    } catch { Write-Warn "pyenv update failed (using the cached list): $_" }

                    $resolved = Resolve-PyenvVersion -Requested $pyver -Available (pyenv install --list)
                    if ($resolved -eq $pyver) {
                        Write-Warn "No pyenv-win definition for $pyver.* — skipping Python install. Pin an exact version in config.yaml (e.g. 3.12.x) or repair 'pyenv update'."
                        $pyver = $null
                    } else {
                        Write-Info "Resolved Python $pyver -> $resolved"
                        $pyver = $resolved
                    }
                }
                if ($pyver) { pyenv install $pyver; pyenv global $pyver }
            }
        }
    }

    Write-Info 'nvm/pyenv PATH wiring is added with the PowerShell profile in Stage 3.'
}
