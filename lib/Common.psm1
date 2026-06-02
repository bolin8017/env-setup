# Common.psm1 — logging, platform detection, shared helpers for the Windows engine.
# Cross-module flags travel via ENVSETUP_* environment variables (mirrors the
# Bash engine's exported DRY_RUN / AUTO_YES / KEEP_EXISTING).

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Write-Info    { param([string]$Message) Write-Host "[INFO] $Message"    -ForegroundColor Cyan }
function Write-Success { param([string]$Message) Write-Host "[OK] $Message"      -ForegroundColor Green }
function Write-Warn    { param([string]$Message) Write-Host "[WARN] $Message"    -ForegroundColor Yellow }
function Write-Err     { param([string]$Message) Write-Host "[ERROR] $Message"   -ForegroundColor Red }
function Write-Header {
    param([string]$Title)
    Write-Host ''
    Write-Host ('=' * 60) -ForegroundColor Blue
    Write-Host "  $Title" -ForegroundColor Blue
    Write-Host ('=' * 60) -ForegroundColor Blue
}

function Test-Command {
    param([Parameter(Mandatory)][string]$Name)
    return $null -ne (Get-Command $Name -ErrorAction SilentlyContinue)
}

function Test-IsWindows {
    # $IsWindows exists only on pwsh 6+. On Windows PowerShell 5.1 it is *unset*
    # (not $null) — and under Set-StrictMode -Version Latest, reading an unset
    # variable is a terminating error (VariableIsUndefined). Probe with
    # Get-Variable instead of referencing $IsWindows directly, then fall back to
    # $env:OS (5.1 only ever runs on Windows, where $env:OS is 'Windows_NT').
    $isWin = Get-Variable -Name IsWindows -ValueOnly -ErrorAction Ignore
    if ($null -ne $isWin) { return [bool]$isWin }
    return ($env:OS -eq 'Windows_NT')
}

function Assert-Windows {
    if (-not (Test-IsWindows)) {
        throw 'The PowerShell engine only runs on native Windows. Use setup.sh on macOS/Linux/WSL.'
    }
}

function Test-DryRun       { return ($env:ENVSETUP_DRY_RUN -eq 'true') }
function Test-AutoYes      { return ($env:ENVSETUP_AUTO_YES -eq 'true') }
function Test-KeepExisting { return ($env:ENVSETUP_KEEP_EXISTING -eq 'true') }
function Test-KeepTools    { return ($env:ENVSETUP_KEEP_TOOLS -eq 'true') }
function Test-Purge        { return ($env:ENVSETUP_PURGE -eq 'true') }
function Test-NoRestore    { return ($env:ENVSETUP_NO_RESTORE -eq 'true') }

function Confirm-Action {
    param([Parameter(Mandatory)][string]$Prompt)
    if (Test-AutoYes) { return $true }
    $answer = Read-Host "$Prompt [y/N]"
    return ($answer -match '^[Yy]')
}

Export-ModuleMember -Function `
    Write-Info, Write-Success, Write-Warn, Write-Err, Write-Header, `
    Test-Command, Test-IsWindows, Assert-Windows, `
    Test-DryRun, Test-AutoYes, Test-KeepExisting, Confirm-Action, `
    Test-KeepTools, Test-Purge, Test-NoRestore
