# Backup.psm1 - timestamped backup of a single file before overwrite.

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

function Get-NewestBakPath {
    # Newest <Path>.bak.* sibling, or $null. Sorted by NAME: the filename stamp
    # (yyyyMMdd_HHmmss) is authoritative and lexically ordered, while
    # LastWriteTime is NOT - Copy-Item preserves the source's mtime, so a
    # manually restored old file yields a "newer" mtime on an older backup.
    param([Parameter(Mandatory)][string]$Path)
    $dir  = Split-Path $Path -Parent
    $leaf = Split-Path $Path -Leaf
    if (-not (Test-Path -LiteralPath $dir)) { return $null }
    $bak = Get-ChildItem -LiteralPath $dir -Filter "$leaf.bak.*" -ErrorAction Ignore |
           Sort-Object Name | Select-Object -Last 1
    if ($bak) { return $bak.FullName } else { return $null }
}

function Restore-NewestBak {
    # Restore <Path> from the newest <Path>.bak.* sibling. No-op when no
    # backup exists. Honours DryRun and NoRestore.
    param([Parameter(Mandatory)][string]$Path)
    if (Test-NoRestore) { return }
    $bak = Get-NewestBakPath -Path $Path
    if (-not $bak) { Write-Info "No backup to restore for $Path"; return }
    $bakName = Split-Path $bak -Leaf
    if (Test-DryRun) { Write-Info "[DRY-RUN] Would restore $Path from $bakName"; return }
    Copy-Item -LiteralPath $bak -Destination $Path -Force
    Write-Success "Restored $Path from $bakName"
}

Export-ModuleMember -Function Backup-File, Restore-NewestBak, Get-NewestBakPath
