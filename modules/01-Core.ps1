#!/usr/bin/env pwsh
# 01-Core.ps1 - scoop buckets + core apps (git, gh). Mirrors 01-core.sh, which
# installs git/gh/build-tools (it configures no git identity, so neither do we).
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module "$PSScriptRoot/../lib/Common.psm1"
Import-Module "$PSScriptRoot/../lib/Config.psm1"
Import-Module "$PSScriptRoot/../lib/Package.psm1"

function Add-ScoopBucket {
    param([Parameter(Mandatory)][string]$Name)
    if (Test-DryRun) { Write-Info "[DRY-RUN] Would add scoop bucket: $Name"; return }
    if (-not (Test-ScoopAvailable)) { return }
    $have = (scoop bucket list 6>$null | Out-String)
    if ($have -notmatch ('(?m)^\s*' + [regex]::Escape($Name) + '\b')) { scoop bucket add $Name }
}

function Install-Core {
    Write-Header 'Core'
    if (-not (Test-DryRun) -and -not (Test-ScoopAvailable)) {
        throw 'scoop not found - run bootstrap.ps1 first'
    }
    Add-ScoopBucket -Name 'extras'   # some CLI tools (e.g. bottom) live here
    if (Test-CfgEnabled 'core.git')        { Install-App -Id 'Git.Git' }
    if (Test-CfgEnabled 'core.github_cli') { Install-App -Id 'GitHub.cli' }
    if (Test-CfgEnabled 'core.build_tools') {
        # The Bash engine installs build-essential; on Windows pyenv-win ships
        # prebuilt CPython, so heavy VS Build Tools are not installed by default.
        Write-Info 'build_tools: skipped on Windows (pyenv-win uses prebuilt CPython).'
    }
}

function Uninstall-Core {
    Write-Header 'Uninstall: Core'
    if (Test-Purge) {
        Write-Warn 'git and gh are widely depended on - removing them per -Purge'
        Remove-App -Id 'GitHub.cli'
        Remove-App -Id 'Git.Git'
    } else {
        Write-Info 'git/gh are system tools - use -Purge to remove them'
    }
}
