# DryRun.psm1 — dry-run wrappers + config deployment with overwrite protection.
# Mirrors lib/dryrun.sh. Reads flags via Common.psm1 (ENVSETUP_* env vars).

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# No -Force: a -Force re-import here would Remove-Module Common and strip its
# functions from a parent script's scope (e.g. setup.ps1). Plain import is a
# no-op once loaded; tests reload with -Force at their own BeforeAll.
Import-Module "$PSScriptRoot/Common.psm1"

function Invoke-OrDryRun {
    param(
        [Parameter(Mandatory)][string]$Description,
        [Parameter(Mandatory)][scriptblock]$Action
    )
    if (Test-DryRun) { Write-Info "[DRY-RUN] Would run: $Description"; return }
    & $Action
}

function Copy-OrDryRun {
    param([Parameter(Mandatory)][string]$Source, [Parameter(Mandatory)][string]$Destination)
    if (Test-DryRun) { Write-Info "[DRY-RUN] Would copy: $Source -> $Destination"; return }
    Copy-Item -LiteralPath $Source -Destination $Destination -Force
}

function New-DirOrDryRun {
    param([Parameter(Mandatory)][string]$Path)
    if (Test-DryRun) { Write-Info "[DRY-RUN] Would mkdir: $Path"; return }
    if (-not (Test-Path -LiteralPath $Path)) { New-Item -ItemType Directory -Path $Path -Force | Out-Null }
}

function Remove-OrDryRun {
    param([Parameter(Mandatory)][string]$Path)
    if (Test-DryRun) { Write-Info "[DRY-RUN] Would remove: $Path"; return }
    if (Test-Path -LiteralPath $Path) { Remove-Item -LiteralPath $Path -Recurse -Force }
}

function Deploy-Config {
    param(
        [Parameter(Mandatory)][string]$Source,
        [Parameter(Mandatory)][string]$Destination,
        [string]$Label
    )
    if (-not $Label) { $Label = Split-Path $Destination -Leaf }

    if (-not (Test-Path -LiteralPath $Source)) { Write-Warn "$Label source not found: $Source"; return }

    if (Test-Path -LiteralPath $Destination) {
        if (Test-KeepExisting) { Write-Info "[SKIP] Keeping existing $Label (KeepExisting)"; return }
        if (-not (Test-AutoYes)) {
            $same = $false
            try { $same = -not (Compare-Object (Get-Content -LiteralPath $Source) (Get-Content -LiteralPath $Destination)) } catch { $same = $false }
            if ($same) { Write-Info "${Label}: identical to repo version — skipping"; return }
            if (-not (Confirm-Action "Overwrite ${Destination}?")) { Write-Info "[SKIP] Keeping existing $Label"; return }
        }
    }

    $parent = Split-Path $Destination -Parent
    if ($parent) { New-DirOrDryRun -Path $parent }
    Copy-OrDryRun -Source $Source -Destination $Destination
    Write-Success "Deployed $Label"
}

Export-ModuleMember -Function Invoke-OrDryRun, Copy-OrDryRun, New-DirOrDryRun, Deploy-Config, Remove-OrDryRun
