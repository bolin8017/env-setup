# Backup.psm1 — timestamped backup of a single file before overwrite.

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# No -Force: a -Force re-import here would Remove-Module Common and strip its
# functions from a parent script's scope. Plain import is a no-op once loaded.
Import-Module "$PSScriptRoot/Common.psm1"

function Backup-File {
    param(
        [Parameter(Mandatory)][string]$Path,
        [string]$Stamp
    )
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    if (-not $Stamp) { $Stamp = (Get-Date -Format 'yyyyMMdd_HHmmss') }
    $bak = "$Path.bak.$Stamp"
    Copy-Item -LiteralPath $Path -Destination $bak -Force
    Write-Info "Backed up $Path -> $bak"
    return $bak
}

Export-ModuleMember -Function Backup-File
