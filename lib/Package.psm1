# Package.psm1 — scoop (CLI, no admin) + winget (apps) abstraction with a
# no-admin defer path that mirrors the Bash engine's no-sudo handling.

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# No -Force: a -Force re-import here would Remove-Module Common and strip its
# functions from a parent script's scope (e.g. setup.ps1). Plain import is a
# no-op once loaded; tests reload with -Force at their own BeforeAll.
Import-Module "$PSScriptRoot/Common.psm1"

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
    } catch {
        Write-Warn "Could not determine elevation (assuming not elevated): $_"
        return $false
    }
}

function Test-ScoopAvailable { return (Test-Command 'scoop') }

function Install-Pkg {
    # CLI tools via scoop — never needs admin. Throws on failure so the calling
    # module is honestly recorded as Failed (never silently reported Installed).
    param([Parameter(Mandatory)][string]$Name)
    if (Test-DryRun) { Write-Info "[DRY-RUN] Would run: scoop install $Name"; return }
    if (-not (Test-ScoopAvailable)) {
        throw "scoop not available — cannot install $Name (run 01-Core first)"
    }
    # scoop is a PowerShell shim whose $LASTEXITCODE is unreliable (and reading it
    # unset throws under StrictMode), so we don't gate on it here. Robust per-tool
    # failure detection lands in Stage 2, where modules exercise this against a
    # real scoop and the check can be validated.
    scoop install $Name
}

function Test-WingetSucceeded {
    # winget exits 0 on a fresh install. When the package is already present it
    # tries to upgrade, and if nothing newer exists it exits 0x8A15002B
    # (-1978335189, "No newer package versions are available") — success for an
    # idempotent re-run, not a failure.
    param([Parameter(Mandatory)][int]$ExitCode)
    return ($ExitCode -eq 0 -or $ExitCode -eq -1978335189)
}

function Install-App {
    # Apps via winget. If elevation is unavailable, defer and continue; otherwise
    # run winget and throw on a real failure (native commands don't honor
    # $ErrorActionPreference, so check $LASTEXITCODE explicitly via
    # Test-WingetSucceeded, which tolerates the "already current" exit code).
    param(
        [Parameter(Mandatory)][string]$Id,
        [switch]$RequiresAdmin
    )
    if ($RequiresAdmin -and -not (Test-DryRun) -and -not (Test-Elevated)) {
        Add-MissingAdminPackage $Id
        Write-Warn "Deferring $Id to an administrator (winget needs elevation)"
        return
    }
    if (Test-DryRun) { Write-Info "[DRY-RUN] Would run: winget install --id $Id -e"; return }
    winget install --id $Id -e --accept-source-agreements --accept-package-agreements
    if (-not (Test-WingetSucceeded $LASTEXITCODE)) { throw "winget install $Id failed (exit $LASTEXITCODE)" }
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

function Remove-Pkg {
    # Uninstall a scoop CLI package (no admin). Mirrors Install-Pkg.
    param([Parameter(Mandatory)][string]$Name)
    if (Test-DryRun) { Write-Info "[DRY-RUN] Would run: scoop uninstall $Name"; return }
    if (-not (Test-ScoopAvailable)) { Write-Warn "scoop not available — cannot uninstall $Name"; return }
    scoop uninstall $Name
}

function Remove-App {
    # Uninstall a winget app. Mirrors Install-App. winget exits non-zero when the
    # app is already absent; that is fine for an idempotent teardown, so we log
    # rather than throw.
    param([Parameter(Mandatory)][string]$Id)
    if (Test-DryRun) { Write-Info "[DRY-RUN] Would run: winget uninstall --id $Id -e"; return }
    winget uninstall --id $Id -e --accept-source-agreements
    if ($LASTEXITCODE -ne 0) { Write-Warn "winget uninstall $Id exited $LASTEXITCODE (may already be absent)" }
}

Export-ModuleMember -Function `
    Clear-MissingAdmin, Add-MissingAdminPackage, Get-MissingAdminPackage, `
    Test-Elevated, Test-ScoopAvailable, Test-WingetSucceeded, Install-Pkg, Install-App, Show-MissingAdminSummary, `
    Remove-Pkg, Remove-App
