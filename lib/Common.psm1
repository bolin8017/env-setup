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
    # $IsWindows exists on pwsh 6+; it is $null on Windows PowerShell 5.1, which
    # only ever runs on Windows. Treat both "true" and "5.1-on-Windows" as Windows.
    if ($null -ne $IsWindows) { return [bool]$IsWindows }
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

function Confirm-Action {
    param([Parameter(Mandatory)][string]$Prompt)
    if (Test-AutoYes) { return $true }
    $answer = Read-Host "$Prompt [y/N]"
    return ($answer -match '^[Yy]')
}

Export-ModuleMember -Function `
    Write-Info, Write-Success, Write-Warn, Write-Err, Write-Header, `
    Test-Command, Test-IsWindows, Assert-Windows, `
    Test-DryRun, Test-AutoYes, Test-KeepExisting, Confirm-Action
