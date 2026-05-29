# Backup.psm1 — timestamped backup of a single file before overwrite.

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module "$PSScriptRoot/Common.psm1" -Force

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
