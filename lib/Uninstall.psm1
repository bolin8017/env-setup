# Uninstall.psm1 - safety primitives for the Windows teardown engine.
# Mirrors lib/uninstall.sh: protected-path guard + managed file/dir removal.

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module "$PSScriptRoot/Common.psm1"
Import-Module "$PSScriptRoot/DryRun.psm1" -DisableNameChecking

function Get-AbsPath {
    param([Parameter(Mandatory)][string]$Path)
    $p = $Path
    if ($p -eq '~') { $p = $HOME }
    elseif ($p.StartsWith('~/') -or $p.StartsWith('~\')) { $p = Join-Path $HOME $p.Substring(2) }
    if (-not [System.IO.Path]::IsPathRooted($p)) { $p = Join-Path (Get-Location).Path $p }
    return $p.TrimEnd('\', '/')
}

function Test-ProtectedPath {
    # Return $true if the path must never be removed.
    param([Parameter(Mandatory)][string]$Path)
    $abs  = Get-AbsPath $Path
    # Get-AbsPath normalizes '/' to '' and 'C:\' to 'C:'; treat filesystem and
    # drive roots as always protected.
    if (-not $abs -or $abs -match '^[A-Za-z]:$') { return $true }
    $home0 = $HOME.TrimEnd('\', '/')
    if ($abs -ieq $home0) { return $true }

    $sep    = [IO.Path]::DirectorySeparatorChar
    $claude = Join-Path $HOME '.claude'
    foreach ($name in @('.credentials.json', 'projects', 'todos', 'shell-snapshots', 'statsig')) {
        $g = (Join-Path $claude $name).TrimEnd('\', '/')
        if ($abs -ieq $g -or $abs.StartsWith($g + $sep, [StringComparison]::OrdinalIgnoreCase)) { return $true }
    }
    if ($abs.StartsWith((Join-Path $claude 'history'), [StringComparison]::OrdinalIgnoreCase)) { return $true }

    if ($env:ENVSETUP_PROTECTED_EXTRA) {
        foreach ($extra in ($env:ENVSETUP_PROTECTED_EXTRA -split "`n")) {
            if (-not $extra) { continue }
            $e = Get-AbsPath $extra
            if ($abs -ieq $e -or $abs.StartsWith($e + $sep, [StringComparison]::OrdinalIgnoreCase)) { return $true }
        }
    }
    return $false
}

function Remove-ManagedFile {
    # Remove $Dest only when byte-identical to $RepoSrc. A modified file is
    # preserved and reported. Protected paths refused.
    param(
        [Parameter(Mandatory)][string]$Dest,
        [Parameter(Mandatory)][string]$RepoSrc,
        [string]$Label
    )
    if (-not $Label) { $Label = Split-Path $Dest -Leaf }
    if (-not (Test-Path -LiteralPath $Dest)) { Write-Info "[SKIP] $Label not present"; return }
    if (Test-ProtectedPath $Dest) { Write-Warn "Refusing to remove protected path: $Dest"; return }
    if (-not $RepoSrc -or -not (Test-Path -LiteralPath $RepoSrc)) {
        Write-Warn "${Label}: cannot verify (no repo source) - preserved"; return
    }
    $same = Test-FileContentEqual -PathA $RepoSrc -PathB $Dest
    if (-not $same) { Write-Warn "$Label modified locally - preserved"; return }
    Remove-OrDryRun -Path $Dest
    Write-Success "Removed $Label"
}

function Remove-ManagedDir {
    # Remove a directory env-setup created (confirmation-gated). Protected refused.
    param([Parameter(Mandatory)][string]$Dir, [string]$Label)
    if (-not $Label) { $Label = Split-Path $Dir -Leaf }
    if (-not (Test-Path -LiteralPath $Dir)) { Write-Info "[SKIP] $Label not present"; return }
    if (Test-ProtectedPath $Dir) { Write-Warn "Refusing to remove protected path: $Dir"; return }
    if (-not (Confirm-Action "Remove $Label ($Dir)?")) { Write-Info "[SKIP] Keeping $Label"; return }
    Remove-OrDryRun -Path $Dir
    Write-Success "Removed $Label"
}

function Remove-ManagedBlock {
    # Strip a begin/end-marker-delimited block from a text file (mirrors
    # strip_block_from_file in lib/uninstall.sh). Lines outside the block are
    # kept verbatim; a missing file or a file without the block is a no-op.
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Begin,
        [Parameter(Mandatory)][string]$End,
        [string]$Label
    )
    if (-not $Label) { $Label = Split-Path $Path -Leaf }
    if (-not (Test-Path -LiteralPath $Path)) { Write-Info "[SKIP] $Label not present"; return }
    $lines = @(Get-Content -LiteralPath $Path)
    if (-not @($lines | Where-Object { $_.Contains($Begin) })) { Write-Info "[SKIP] no managed block in $Label"; return }
    if (Test-DryRun) { Write-Info "[DRY-RUN] Would strip the managed block from $Path"; return }
    $skip = $false
    $kept = @(foreach ($l in $lines) {
        if ($l.Contains($Begin)) { $skip = $true }
        if (-not $skip) { $l }
        if ($l.Contains($End)) { $skip = $false }
    })
    $content = if ($kept.Count) { ($kept -join "`n") + "`n" } else { '' }
    Write-Utf8NoBom -Path $Path -Content $content
    Write-Success "Stripped the managed block from $Label"
}

Export-ModuleMember -Function Get-AbsPath, Test-ProtectedPath, Remove-ManagedFile, Remove-ManagedDir, Remove-ManagedBlock
