#!/usr/bin/env pwsh
# claude-swap.ps1 - PowerShell entry for the claude-swap bash helper deployed
# next to it in ~/.local/bin (source: scripts/claude-swap.sh). The swap logic
# lives in the bash script; this shim only locates Git Bash and forwards.
# Never invoke a bare `bash` here: with WSL installed, PATH resolves it to the
# WSL launcher (WindowsApps bash.exe), whose /bin/bash cannot see Windows
# paths and fails with "No such file or directory". Deployed by
# 08-ClaudeCode.ps1; the claude-swap function in configs/aliases.ps1
# delegates here, and PowerShell's command resolution prefers this .ps1 over
# the extensionless bash script for plain `claude-swap` in profile-less shells.

$helper = Join-Path $HOME '.local/bin/claude-swap'
if (-not (Test-Path -LiteralPath $helper)) {
    Write-Error 'claude-swap: bash helper not deployed - run setup module 08-ClaudeCode first'
    exit 1
}

# Ask git itself where it lives (--exec-path is <root>/mingw64/libexec/git-core)
# so scoop/custom layouts work; fall back to the default install path.
$gitBash = $null
if (Get-Command git.exe -ErrorAction Ignore) {
    $execPath = & git.exe --exec-path 2>$null
    if ($execPath) {
        $candidate = [System.IO.Path]::GetFullPath((Join-Path $execPath '../../../bin/bash.exe'))
        if (Test-Path -LiteralPath $candidate) { $gitBash = $candidate }
    }
}
if (-not $gitBash) {
    $candidate = Join-Path $env:ProgramFiles 'Git/bin/bash.exe'
    if (Test-Path -LiteralPath $candidate) { $gitBash = $candidate }
}
if (-not $gitBash) {
    Write-Error 'claude-swap: Git Bash not found - install Git for Windows'
    exit 1
}

# Git Bash eats backslashes in Windows paths (C:\Users\... arrives as
# C:Users...); it accepts forward slashes for the same path.
& $gitBash ($helper -replace '\\', '/') @args
exit $LASTEXITCODE
