# Package.psm1 — scoop (CLI, no admin) + winget (apps) abstraction with a
# no-admin defer path that mirrors the Bash engine's no-sudo handling.

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module "$PSScriptRoot/Common.psm1" -Force
Import-Module "$PSScriptRoot/DryRun.psm1" -Force

$script:MissingAdminPackages = [System.Collections.Generic.List[string]]::new()

function Clear-MissingAdmin { $script:MissingAdminPackages.Clear() }
function Add-MissingAdminPackage {
    param([Parameter(Mandatory)][string]$Id)
    if (-not $script:MissingAdminPackages.Contains($Id)) { [void]$script:MissingAdminPackages.Add($Id) }
}
function Get-MissingAdminPackage { return [string[]]@($script:MissingAdminPackages) }

function Test-Elevated {
    # True if the current process can perform admin actions. On non-Windows
    # (CI cross-checks) default to false so the defer path is exercised.
    if (-not (Test-IsWindows)) { return $false }
    try {
        $id = [System.Security.Principal.WindowsIdentity]::GetCurrent()
        $p  = [System.Security.Principal.WindowsPrincipal]::new($id)
        return $p.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)
    } catch { return $false }
}

function Test-ScoopAvailable { return (Test-Command 'scoop') }

function Install-Pkg {
    # CLI tools via scoop — never needs admin.
    param([Parameter(Mandatory)][string]$Name)
    if (-not (Test-DryRun) -and -not (Test-ScoopAvailable)) {
        Write-Warn "scoop not available — cannot install $Name"; return
    }
    Invoke-OrDryRun -Description "scoop install $Name" -Action { scoop install $Name }
}

function Install-App {
    # Apps via winget. If elevation is unavailable, defer and continue.
    param(
        [Parameter(Mandatory)][string]$Id,
        [switch]$RequiresAdmin
    )
    if ($RequiresAdmin -and -not (Test-DryRun) -and -not (Test-Elevated)) {
        Add-MissingAdminPackage $Id
        Write-Warn "Deferring $Id to an administrator (winget needs elevation)"
        return
    }
    Invoke-OrDryRun -Description "winget install --id $Id -e" -Action {
        winget install --id $Id -e --accept-source-agreements --accept-package-agreements
    }
}

function Show-MissingAdminSummary {
    if ($script:MissingAdminPackages.Count -eq 0) { return }
    Write-Header 'Administrator Action Required'
    Write-Host '  winget could not elevate on this machine. Ask an administrator to run:'
    Write-Host ''
    foreach ($id in $script:MissingAdminPackages) {
        Write-Host "    winget install --id $id -e"
    }
    Write-Host ''
    Write-Host '  Then re-run setup.ps1 to continue.'
}

Export-ModuleMember -Function `
    Clear-MissingAdmin, Add-MissingAdminPackage, Get-MissingAdminPackage, `
    Test-Elevated, Test-ScoopAvailable, Install-Pkg, Install-App, Show-MissingAdminSummary
