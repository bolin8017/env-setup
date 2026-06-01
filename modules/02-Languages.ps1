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

function Update-PyenvVersionCache {
    # pyenv-win refreshes its installable-version list with 'pyenv update', but
    # that uses an htmlfile COM object unsupported on current Windows 11
    # ("htmlfile: this method is not supported"), so it fails and the list goes
    # stale. Replace the cache file directly from the maintained source — no
    # htmlfile. Best-effort: on failure pyenv keeps its existing list.
    try {
        $cache = Join-Path (scoop prefix pyenv) 'pyenv-win\.versions_cache.xml'
        [Net.ServicePointManager]::SecurityProtocol =
            [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
        $url = 'https://raw.githubusercontent.com/pyenv-win/pyenv-win/master/pyenv-win/.versions_cache.xml'
        Invoke-WebRequest -UseBasicParsing -Uri $url -OutFile $cache
        Write-Info 'Refreshed pyenv-win version list (.versions_cache.xml)'
    } catch {
        Write-Warn "Could not refresh the pyenv version list (using the existing one): $_"
    }
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
                    Update-PyenvVersionCache
                    $resolved = Resolve-PyenvVersion -Requested $pyver -Available (pyenv install --list)
                    if ($resolved -eq $pyver) {
                        Write-Warn "No pyenv-win definition for $pyver.* — the version list may be stale. Pin an exact version in config.yaml."
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
