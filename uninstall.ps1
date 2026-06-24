#!/usr/bin/env pwsh
# uninstall.ps1 - Windows (native PowerShell) teardown entry point.
# Sibling of setup.ps1; reverses each module's Uninstall-<Module> (09 -> 01).
[CmdletBinding()]
param(
    [switch]$DryRun,
    [Alias('y')][switch]$AutoYes,
    [switch]$KeepTools,
    [switch]$Purge,
    [switch]$NoRestore,
    [string]$Config,
    [string]$Modules,
    [switch]$Help
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ($PSVersionTable.PSEdition -eq 'Desktop') {
    try { [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new() }
    catch { Write-Verbose "Could not set console to UTF-8: $_" }
}

$RepoDir = $PSScriptRoot
Import-Module "$RepoDir/lib/Common.psm1" -Force
Import-Module "$RepoDir/lib/Config.psm1" -Force
Import-Module "$RepoDir/lib/Package.psm1" -Force
Import-Module "$RepoDir/lib/DryRun.psm1" -Force -DisableNameChecking
Import-Module "$RepoDir/lib/Backup.psm1" -Force
Import-Module "$RepoDir/lib/Uninstall.psm1" -Force
Import-Module "$RepoDir/lib/ClaudeConfig.psm1" -Force

function Show-Usage {
    @'
Usage: ./uninstall.ps1 [OPTIONS]

Removes what env-setup installed. Conservative by default.

  -DryRun         Print what would be removed without making changes
  -AutoYes, -y    Remove without prompting (protected paths still blocked)
  -KeepTools      Remove only config; keep user-space tools (scoop/PSGallery)
  -Purge          Also remove apps (PowerShell 7, Oh My Posh, git/gh, CLI tools)
  -NoRestore      Skip restoring settings from backup
  -Config <path>  Custom config.yaml (read only for protected paths)
  -Modules <list> Comma-separated modules, e.g. 06-Shell,08-ClaudeCode
  -Help           Show this help message

Never removed: personal data directories, Claude credentials/history.
'@ | Write-Output
}

function Test-ModuleInFilter {
    param([string]$Name, [string[]]$Filter)
    if (-not $Filter) { return $true }
    foreach ($entry in $Filter) {
        if ($entry -eq $Name) { return $true }
        $prefix = [System.Management.Automation.WildcardPattern]::Escape($entry)
        if ($Name -like ($prefix + '-*')) { return $true }
    }
    return $false
}

# Tests dot-source this script with ENVSETUP_UNINSTALL_NORUN set.
if ($env:ENVSETUP_UNINSTALL_NORUN) { return }

if ($Help) { Show-Usage; exit 0 }

Assert-Windows

if ($KeepTools -and $Purge) { Write-Err '-KeepTools and -Purge cannot be combined'; exit 1 }

$env:ENVSETUP_DRY_RUN    = if ($DryRun)    { 'true' } else { 'false' }
$env:ENVSETUP_AUTO_YES   = if ($AutoYes)   { 'true' } else { 'false' }
$env:ENVSETUP_KEEP_TOOLS = if ($KeepTools) { 'true' } else { 'false' }
$env:ENVSETUP_PURGE      = if ($Purge)     { 'true' } else { 'false' }
$env:ENVSETUP_NO_RESTORE = if ($NoRestore) { 'true' } else { 'false' }

Import-Config -Path $Config
if (Test-CfgEnabled 'general.dry_run') { $env:ENVSETUP_DRY_RUN = 'true' }

# Protected user_dirs paths (newline-separated absolutes).
$env:ENVSETUP_PROTECTED_EXTRA = ((Get-CfgList 'user_dirs.paths' | ForEach-Object { Join-Path $HOME $_ }) -join "`n")

# Reverse module order (09 -> 01; 04-Docker has no Windows engine).
$ModuleList = @(
    @{ Name = '10-Worklog';     Fn = 'Uninstall-Worklog' }
    @{ Name = '09-UserDirs';    Fn = 'Uninstall-UserDirs' }
    @{ Name = '08-ClaudeCode';  Fn = 'Uninstall-ClaudeCode' }
    @{ Name = '07-Multiplexer'; Fn = 'Uninstall-Multiplexer' }
    @{ Name = '06-Shell';       Fn = 'Uninstall-Shell' }
    @{ Name = '05-CliTools';    Fn = 'Uninstall-CliTools' }
    @{ Name = '03-PythonTools'; Fn = 'Uninstall-PythonTools' }
    @{ Name = '02-Languages';   Fn = 'Uninstall-Languages' }
    @{ Name = '01-Core';        Fn = 'Uninstall-Core' }
)

$filter = @()
if ($Modules) { $filter = @($Modules.Split(',').Trim()) }
$done = @(); $skipped = @(); $failed = @()

Write-Host ''
Write-Host '  env-setup - Uninstaller' -ForegroundColor Red
Write-Host "  Dry-run: $($env:ENVSETUP_DRY_RUN)  KeepTools: $($env:ENVSETUP_KEEP_TOOLS)  Purge: $($env:ENVSETUP_PURGE)" -ForegroundColor Cyan
Write-Host ''

if (-not $DryRun -and -not $AutoYes) {
    if (-not (Confirm-Action 'Remove env-setup-managed files (and tools unless -KeepTools)?')) {
        Write-Info 'Aborted by user'; exit 0
    }
}

foreach ($m in $ModuleList) {
    if (-not (Test-ModuleInFilter -Name $m.Name -Filter $filter)) { $skipped += "$($m.Name) (filtered)"; continue }
    $file = Join-Path $RepoDir "modules/$($m.Name).ps1"
    if (-not (Test-Path $file)) { Write-Warn "Module not found: $file"; $skipped += "$($m.Name) (missing)"; continue }
    try {
        . $file
        if (-not (Get-Command $m.Fn -ErrorAction SilentlyContinue)) {
            Write-Err "Function $($m.Fn) not found in $file"; $failed += $m.Name; continue
        }
        & $m.Fn
        $done += $m.Name
    } catch {
        Write-Err "Module $($m.Name) failed: $($_.Exception.Message)"
        Write-Err "  at $($_.InvocationInfo.PositionMessage)"
        $failed += $m.Name
    }
}

Write-Header 'Uninstall Summary'
Write-Host "  Processed: $($done -join ', ')"    -ForegroundColor Green
Write-Host "  Skipped:   $($skipped -join ', ')" -ForegroundColor Yellow
if ($failed.Count -gt 0) { Write-Host "  Failed:    $($failed -join ', ')" -ForegroundColor Red }
Write-Host ''
Write-Host '  Note: ~/.claude data (auth/history) and personal folders were preserved.' -ForegroundColor Cyan

Show-MissingAdminSummary

if ($failed.Count -gt 0) { exit 1 }
exit 0
