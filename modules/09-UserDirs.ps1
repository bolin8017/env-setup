#!/usr/bin/env pwsh
# 09-UserDirs.ps1 — create personal directories under $HOME (mirrors 09-user-dirs.sh).
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module "$PSScriptRoot/../lib/Common.psm1"
Import-Module "$PSScriptRoot/../lib/Config.psm1"
Import-Module "$PSScriptRoot/../lib/DryRun.psm1"

function Install-UserDirs {
    Write-Header 'User directories'
    if (-not (Test-CfgEnabled 'user_dirs.enabled')) {
        Write-Info 'user_dirs disabled — skipping'
        return
    }
    foreach ($rel in (Get-CfgList 'user_dirs.paths')) {
        New-DirOrDryRun -Path (Join-Path $HOME $rel)
    }
}
