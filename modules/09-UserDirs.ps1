#!/usr/bin/env pwsh
# 09-UserDirs.ps1 — create personal directories under $HOME (mirrors 09-user-dirs.sh).
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module "$PSScriptRoot/../lib/Common.psm1"
Import-Module "$PSScriptRoot/../lib/Config.psm1"
Import-Module "$PSScriptRoot/../lib/DryRun.psm1" -DisableNameChecking  # WinPS 5.1: 'Deploy' is an unapproved verb

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

function Uninstall-UserDirs {
    Write-Header 'Uninstall: User directories'
    if (Test-KeepTools) { Write-Info 'Skipping user-dir reclamation (-KeepTools)'; return }
    foreach ($rel in (Get-CfgList 'user_dirs.paths')) {
        $target = Join-Path $HOME $rel
        if (-not (Test-Path -LiteralPath $target)) { Write-Info "[SKIP] $rel not present"; continue }
        $hasChildren = @(Get-ChildItem -LiteralPath $target -Force -ErrorAction Ignore).Count -gt 0
        if ($hasChildren) { Write-Info "$rel contains data — left intact"; continue }
        if (Test-DryRun) { Write-Info "[DRY-RUN] Would remove empty dir: $target"; continue }
        # No -Recurse: physically cannot delete data even if a race fills the dir.
        try { Remove-Item -LiteralPath $target -Force -ErrorAction Stop; Write-Success "Removed empty dir $rel" }
        catch { Write-Info "$rel not removable — left intact" }
    }
}
