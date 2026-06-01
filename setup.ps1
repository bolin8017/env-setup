#!/usr/bin/env pwsh
# setup.ps1 — Windows (native PowerShell) entrypoint for env-setup.
# Sibling of setup.sh; reads the same config.yaml. Runs only on native Windows.

[CmdletBinding()]
param(
    [switch]$DryRun,
    [Alias('y')][switch]$AutoYes,
    [switch]$KeepExisting,
    [string]$Config,
    [switch]$Verify,
    [string]$Modules,
    [switch]$Help
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Windows PowerShell 5.1 defaults the console to the OEM code page, so the
# em-dashes in our banners render as "??". Force UTF-8 output (pwsh 7 already
# defaults to it); guarded because some hosts disallow setting it.
if ($PSVersionTable.PSEdition -eq 'Desktop') {
    try { [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new() }
    catch { Write-Verbose "Could not set console to UTF-8: $_" }
}

$RepoDir = $PSScriptRoot
Import-Module "$RepoDir/lib/Common.psm1" -Force
Import-Module "$RepoDir/lib/Config.psm1" -Force
Import-Module "$RepoDir/lib/Package.psm1" -Force

function Show-Usage {
    @'
Usage: ./setup.ps1 [OPTIONS]

Options:
  -DryRun            Print what would be done without making changes
  -AutoYes, -y       Overwrite existing files without prompting
  -KeepExisting      Keep existing files (skip if destination exists)
  -Config <path>     Use a custom config.yaml file
  -Verify            Run verification only (no installation)
  -Modules <list>    Comma-separated modules to run, e.g. 01-Core,06-Shell
  -Help              Show this help message
'@ | Write-Output
}

function Test-ModuleInFilter {
    # Mirror setup.sh::_module_in_filter — match a filter entry by full name OR
    # numeric prefix, so `-Modules 06` selects `06-Shell` like `--modules 06`.
    # Escape the entry so a value like `[0` is matched as a literal prefix rather
    # than an invalid -like wildcard pattern (which would throw and abort the run).
    param([string]$Name, [string[]]$Filter)
    if (-not $Filter) { return $true }   # $null or empty → select everything
    foreach ($entry in $Filter) {
        if ($entry -eq $Name) { return $true }
        $prefix = [System.Management.Automation.WildcardPattern]::Escape($entry)
        if ($Name -like ($prefix + '-*')) { return $true }
    }
    return $false
}

function Show-Welcome {
    Write-Host ''
    Write-Host '  env-setup — Windows PowerShell engine' -ForegroundColor Blue
    Write-Host "  Dry-run: $($env:ENVSETUP_DRY_RUN)" -ForegroundColor Cyan
    Write-Host ''
}

# Tests dot-source this script with ENVSETUP_SETUP_NORUN set to exercise the
# helper functions above without running the installer.
if ($env:ENVSETUP_SETUP_NORUN) { return }

if ($Help) { Show-Usage; exit 0 }

Assert-Windows

# Cross-module flags via environment (mirrors exported DRY_RUN/AUTO_YES/KEEP_EXISTING).
if ($KeepExisting -and $AutoYes) { Write-Err '-AutoYes and -KeepExisting cannot be combined'; exit 1 }
$env:ENVSETUP_DRY_RUN       = if ($DryRun) { 'true' } else { 'false' }
$env:ENVSETUP_AUTO_YES      = if ($AutoYes) { 'true' } else { 'false' }
$env:ENVSETUP_KEEP_EXISTING = if ($KeepExisting) { 'true' } else { 'false' }

Import-Config -Path $Config
# config.yaml general.* can also turn dry-run on
if (Test-CfgEnabled 'general.dry_run') { $env:ENVSETUP_DRY_RUN = 'true' }
if ((Test-CfgEnabled 'general.auto_yes') -and -not $KeepExisting) { $env:ENVSETUP_AUTO_YES = 'true' }

if ($Verify) {
    $v = Join-Path $RepoDir 'scripts/verify.ps1'
    if (Test-Path $v) { & $v; exit $LASTEXITCODE }
    Write-Warn 'scripts/verify.ps1 not present yet — nothing to verify'
    exit 0
}

# Ordered module list (mirrors setup.sh). 04-Docker intentionally absent.
$ModuleList = @(
    @{ Name = '01-Core';        Fn = 'Install-Core' }
    @{ Name = '02-Languages';   Fn = 'Install-Languages' }
    @{ Name = '03-PythonTools'; Fn = 'Install-PythonTools' }
    @{ Name = '05-CliTools';    Fn = 'Install-CliTools' }
    @{ Name = '06-Shell';       Fn = 'Install-Shell' }
    @{ Name = '07-Multiplexer'; Fn = 'Install-Multiplexer' }
    @{ Name = '08-ClaudeCode';  Fn = 'Install-ClaudeCode' }
    @{ Name = '09-UserDirs';    Fn = 'Install-UserDirs' }
)

# Assign the filter directly as an array. `$x = if (...) { } else { @() }` would
# yield $null (an empty array emits nothing from a block), and binding @()/$null
# to a [string[]] param then crashes on .Count under StrictMode. Also wrap in @()
# so a single value ('X'.Split(',').Trim() returns a scalar) stays an array.
$filter = @()
if ($Modules) { $filter = @($Modules.Split(',').Trim()) }
$installed = @(); $skipped = @(); $failed = @()

Show-Welcome

foreach ($m in $ModuleList) {
    if (-not (Test-ModuleInFilter -Name $m.Name -Filter $filter)) {
        $skipped += "$($m.Name) (filtered)"; continue
    }
    $file = Join-Path $RepoDir "modules/$($m.Name).ps1"
    if (-not (Test-Path $file)) {
        Write-Warn "Module file not found: $file — skipping"
        $skipped += "$($m.Name) (missing)"; continue
    }
    Write-Header $m.Name
    try {
        . $file
        if (-not (Get-Command $m.Fn -ErrorAction SilentlyContinue)) {
            Write-Err "Function $($m.Fn) not found in $file"; $failed += $m.Name; continue
        }
        & $m.Fn
        $installed += $m.Name
    } catch {
        Write-Err "Module $($m.Name) failed: $($_.Exception.Message)"
        Write-Err "  at $($_.InvocationInfo.PositionMessage)"
        $failed += $m.Name
    }
}

Write-Header 'Summary'
Write-Host "  Installed: $($installed -join ', ')" -ForegroundColor Green
Write-Host "  Skipped:   $($skipped -join ', ')"  -ForegroundColor Yellow
if ($failed.Count -gt 0) { Write-Host "  Failed:    $($failed -join ', ')" -ForegroundColor Red }

Show-MissingAdminSummary

if ($failed.Count -gt 0) { exit 1 }
exit 0
